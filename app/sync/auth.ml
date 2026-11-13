module Cap_error = Herbier_bindings.Cap_error
module Cap_preferences = Herbier_bindings.Cap_preferences
module Cap_social_login = Herbier_bindings.Cap_social_login
module Cap_app = Herbier_bindings.Cap_app

type status =
  | Unconfigured
  | Restoring
  | Signed_out
  | Signed_in of {email : string option}

type error =
  | Not_configured
  | Replaced
  | Cancelled
  | Google of Cap_error.t
  | Not_allowed
  | Network of string
  | Server of Gotrue.error
  | Storage of Cap_error.t
  | Crypto of string
  | No_session

let error_to_string = function
  | Not_configured -> "sign-in not configured in this build"
  | Replaced -> "replaced by a newer sign-in"
  | Cancelled -> "cancelled"
  | Google e -> "google: " ^ Cap_error.to_string e
  | Not_allowed -> "no Herbier user for this Google account"
  | Network m -> "network: " ^ m
  | Server e -> "server: " ^ Gotrue.error_to_string e
  | Storage e -> "preferences: " ^ Cap_error.to_string e
  | Crypto m -> "crypto: " ^ m
  | No_session -> "signed out"

let equal_status a b =
  match (a, b) with
  | Unconfigured, Unconfigured | Restoring, Restoring | Signed_out, Signed_out
    ->
      true
  | Signed_in {email = a}, Signed_in {email = b} ->
      Option.equal String.equal a b
  | (Unconfigured | Restoring | Signed_out | Signed_in _), _ -> false

(* [Off]: this build cannot sign in. [Reading]: Preferences not read yet.
   The status is derived from it, so that the two cannot disagree. *)
type phase = Off | Reading | Ready of Session.t option

(* style: mutable fields because the session, its timer and the flights in
   progress change from future, timer and app-state callbacks, outside any
   reaction; nothing outside this module sees them. *)
type t = {
  mutable phase : phase;
  mutable on_change : status -> unit;
  mutable started : bool;
  mutable foreground : bool;
  mutable sign_in_attempt : int;
      (* The latest [sign_in] call: an older one's result is dropped, so that
         a flight that never ends cannot block the next one. *)
  mutable generation : int;
      (* Bumped when a sign-in, a sign-out or a revoked refresh replaces the
         session: a refresh or restore that resolves under an older
         generation changes nothing. *)
  mutable refreshing : (Session.t, error) result Fut.t option;
  mutable failed_refreshes : int;
  mutable timer : Brr.G.timer_id option;
  mutable initialized : (unit, Cap_error.t) result Fut.t option;
  mutable writes : unit Fut.t;
}

let key = "auth.session"
let timeout_ms = 15_000
let log m = Brr.Console.(log [str ("auth: " ^ m)])
let warn m = Brr.Console.(warn [str ("auth: " ^ m)])
let console_error m = Brr.Console.(error [str ("auth: " ^ m)])

let create () =
  let configured =
    not
      (List.exists (String.equal "")
         [
           Backend.supabase_url;
           Backend.publishable_key;
           Backend.google_web_client_id;
         ])
  in
  {
    phase = (match configured with true -> Reading | false -> Off);
    on_change = ignore;
    started = false;
    foreground = true;
    sign_in_attempt = 0;
    generation = 0;
    refreshing = None;
    failed_refreshes = 0;
    timer = None;
    initialized = None;
    writes = Fut.return ();
  }

let status t =
  match t.phase with
  | Off -> Unconfigured
  | Reading -> Restoring
  | Ready None -> Signed_out
  | Ready (Some s) -> Signed_in {email = s.email}

let session t = match t.phase with Ready s -> s | Off | Reading -> None

let session_expires_at t =
  Option.map (fun (s : Session.t) -> s.expires_at) (session t)

let set_phase t phase =
  let before = status t in
  t.phase <- phase;
  let after = status t in
  match equal_status before after with true -> () | false -> t.on_change after

let now () = Ptime_clock.now ()

let expiry_line (s : Session.t) =
  "expires " ^ Ptime.to_rfc3339 ~tz_offset_s:0 s.expires_at

(* Every write of the Preferences key runs here, after the previous one has
   resolved, together with the in-memory change that goes with it: a write
   never lands after a later one, and each step sees what the earlier steps
   did. *)
let serially t step =
  let run = Fut.bind t.writes step in
  t.writes <- Fut.map ignore run;
  run

let message e = Jstr.to_string (Jv.Error.message e)

(* A non-2xx status is not an [Error]: the {!Gotrue} decoders classify it.
   Building the headers throws on a value fetch refuses (a control character
   in the build's key): that is an [Error] too, not an exception that would
   leave the caller's future pending. *)
let post (r : Gotrue.request) =
  match
    Brr_io.Fetch.Headers.of_assoc
      (List.map (fun (k, v) -> (Jstr.v k, Jstr.v v)) r.headers)
  with
  | exception Jv.Error e -> Fut.return (Error (message e))
  | headers ->
      let abort = Brr.Abort.controller () in
      let timed_out = ref false in
      let timer =
        Brr.G.set_timeout ~ms:timeout_ms (fun () ->
            timed_out := true;
            Brr.Abort.abort abort)
      in
      let failed e =
        match !timed_out with true -> "timeout" | false -> message e
      in
      let init =
        Brr_io.Fetch.Request.init ~method':(Jstr.v "POST") ~headers
          ?body:
            (Option.map (fun b -> Brr_io.Fetch.Body.of_jstr (Jstr.v b)) r.body)
          ~signal:(Brr.Abort.signal abort) ()
      in
      let open Fut.Syntax in
      let+ result =
        let* response = Brr_io.Fetch.url ~init (Jstr.v r.url) in
        match response with
        | Error e -> Fut.return (Error (failed e))
        | Ok response -> (
            let+ body =
              Brr_io.Fetch.Body.text (Brr_io.Fetch.Response.as_body response)
            in
            match body with
            | Ok body ->
                Ok (Brr_io.Fetch.Response.status response, Jstr.to_string body)
            | Error e -> Error (failed e))
      in
      Brr.G.stop_timer timer;
      result

let bytes_of a =
  let b = Brr.Tarray.to_bigarray1 a in
  String.init (Bigarray.Array1.dim b) (fun i ->
      Char.chr (Bigarray.Array1.get b i))

let random_hex n =
  let a = Brr.Tarray.create Brr.Tarray.Uint8 n in
  match Brr_webcrypto.Crypto.(set_random_values crypto a) with
  | () -> Ok (Nonce.hex (bytes_of a))
  | exception Jv.Error e -> Error (Crypto (message e))

let sha256_hex text =
  let subtle = Brr_webcrypto.Crypto.(subtle crypto) in
  let algo = Brr_webcrypto.Crypto_algo.(v sha_256) in
  match
    Brr_webcrypto.Subtle_crypto.digest subtle algo
      (Brr.Tarray.of_jstr (Jstr.v text))
  with
  | fut ->
      Fut.map
        (function
          | Ok digest ->
              Ok
                (Nonce.hex
                   (bytes_of (Brr.Tarray.of_buffer Brr.Tarray.Uint8 digest)))
          | Error e -> Error (Crypto (message e)))
        fut
  | exception Jv.Error e -> Fut.return (Error (Crypto (message e)))

let stop_timer t =
  Option.iter Brr.G.stop_timer t.timer;
  t.timer <- None

let ms_of span =
  let ms = Ptime.Span.to_float_s span *. 1000. in
  Float.to_int (Float.max 0. (Float.min ms 1e9))

let remove_logged () =
  Fut.map
    (function
      | Ok () -> ()
      | Error e ->
          console_error ("session not removed: " ^ Cap_error.to_string e))
    (Cap_preferences.remove ~key)

let rec schedule t span =
  stop_timer t;
  match (t.foreground, session t) with
  | false, _ | true, None -> ()
  | true, Some _ ->
      t.timer <-
        Some
          (Brr.G.set_timeout ~ms:(ms_of span) (fun () ->
               t.timer <- None;
               Fut.await (refresh t) ignore))

and refresh t =
  match (t.refreshing, session t) with
  | Some flight, _ -> flight
  | None, None -> Fut.return (Error No_session)
  | None, Some s ->
      let flight = run_refresh t s in
      t.refreshing <- Some flight;
      Fut.await flight (fun _ -> t.refreshing <- None);
      flight

and run_refresh t (s : Session.t) =
  let generation = t.generation in
  let sent = now () in
  let open Fut.Syntax in
  let* answer =
    post
      (Gotrue.refresh_grant ~base_url:Backend.supabase_url
         ~apikey:Backend.publishable_key ~refresh_token:s.refresh_token)
  in
  let decoded =
    match answer with
    | Error m -> Error (Network m)
    | Ok (status, body) ->
        Result.map_error
          (fun e -> Server e)
          (Gotrue.decode_session ~now:sent ~status body)
  in
  serially t (fun () -> refreshed t ~generation decoded)

and refreshed t ~generation decoded =
  let open Fut.Syntax in
  match (t.generation = generation, decoded) with
  | false, _ -> (
      (* A sign-in or sign-out happened meanwhile: its session stands. *)
      match session t with
      | Some current -> Fut.return (Ok current)
      | None -> Fut.return (Error No_session))
  | true, Ok fresh ->
      let+ stored = Cap_preferences.set ~key ~value:(Session.to_string fresh) in
      (match stored with
      | Ok () -> ()
      | Error e ->
          (* The stored refresh token is already rotated out: the next launch
             may come up signed out. *)
          console_error
            ("refreshed session not stored: " ^ Cap_error.to_string e));
      t.failed_refreshes <- 0;
      set_phase t (Ready (Some fresh));
      log ("refreshed, " ^ expiry_line fresh);
      schedule t (Session.refresh_in ~now:(now ()) fresh);
      Ok fresh
  | true, Error (Server e) when Gotrue.revokes_session e ->
      warn ("session revoked: " ^ Gotrue.error_to_string e);
      t.generation <- t.generation + 1;
      t.failed_refreshes <- 0;
      stop_timer t;
      set_phase t (Ready None);
      let+ () = remove_logged () in
      Error No_session
  | true, Error e ->
      t.failed_refreshes <- t.failed_refreshes + 1;
      let delay = Session.retry_delay ~attempt:t.failed_refreshes in
      warn
        (Printf.sprintf "refresh failed (%s), retry in %.0f s"
           (error_to_string e)
           (Ptime.Span.to_float_s delay));
      schedule t delay;
      Fut.return (Error e)

let resume t =
  t.foreground <- true;
  match session t with
  | None -> ()
  | Some s -> (
      match Session.due ~now:(now ()) s with
      | true -> Fut.await (refresh t) ignore
      | false -> schedule t (Session.refresh_in ~now:(now ()) s))

let pause t =
  t.foreground <- false;
  stop_timer t;
  log "background, timer stopped"

let on_state = function Cap_app.Active -> resume | Cap_app.Inactive -> pause

let access_token t =
  match session t with
  | None -> Fut.return (Error No_session)
  | Some s when not (Session.due ~now:(now ()) s) ->
      Fut.return (Ok s.access_token)
  | Some _ ->
      Fut.map
        (function
          | Ok (fresh : Session.t) -> Ok fresh.access_token
          | Error e -> (
              match session t with
              | Some current when not (Session.expired ~now:(now ()) current) ->
                  Ok current.access_token
              | Some _ | None -> Error e))
        (refresh t)

let refresh_now t = Fut.map (Result.map ignore) (refresh t)

let debug_expire t =
  match session t with
  | None -> ()
  | Some s ->
      let at =
        Ptime.add_span (now ())
          (Ptime.Span.add Session.refresh_margin (Ptime.Span.of_int_s 30))
      in
      Option.iter
        (fun at ->
          let s = Session.with_expiry at s in
          set_phase t (Ready (Some s));
          log ("expiry moved, " ^ expiry_line s);
          schedule t (Session.refresh_in ~now:(now ()) s))
        at

let restore t =
  let generation = t.generation in
  Fut.map
    (fun stored ->
      match t.generation = generation with
      | false -> ()
      | true -> (
          match stored with
          | Error e ->
              console_error ("session not read: " ^ Cap_error.to_string e);
              set_phase t (Ready None)
          | Ok None -> set_phase t (Ready None)
          | Ok (Some text) -> (
              match Session.of_string text with
              | Ok s ->
                  set_phase t (Ready (Some s));
                  log ("session restored, " ^ expiry_line s)
              | Error reason ->
                  warn ("stored session dropped: " ^ reason);
                  set_phase t (Ready None);
                  Fut.await
                    (serially t (fun () ->
                         match t.generation = generation with
                         | false -> Fut.return ()
                         | true -> remove_logged ()))
                    ignore)))
    (Cap_preferences.get ~key)

let start t ~on_change =
  match (t.started, t.phase) with
  | true, _ | false, Off -> t.started <- true
  | false, (Reading | Ready _) ->
      t.started <- true;
      t.on_change <- on_change;
      Fut.await (restore t) (fun () ->
          Fut.await
            (Cap_app.on_state_change (fun s -> on_state s t))
            (function
              | Ok (_ : Cap_app.listener) -> ()
              | Error e -> warn ("app state listener: " ^ Cap_error.to_string e));
          match t.foreground with true -> resume t | false -> ())

let initialize t =
  match t.initialized with
  | Some f -> f
  | None ->
      let f =
        Cap_social_login.initialize_google
          ~web_client_id:Backend.google_web_client_id
      in
      t.initialized <- Some f;
      Fut.await f (function Ok () -> () | Error _ -> t.initialized <- None);
      f

let logout_server (s : Session.t) =
  Fut.await
    (post
       (Gotrue.logout ~base_url:Backend.supabase_url
          ~apikey:Backend.publishable_key ~access_token:s.access_token))
    (function
      | Error m -> warn ("server logout: network: " ^ m)
      | Ok (status, body) -> (
          match Gotrue.decode_empty ~status body with
          | Ok () -> ()
          | Error e -> warn ("server logout: " ^ Gotrue.error_to_string e)))

let exchange ~raw ~id_token =
  let sent = now () in
  Fut.map
    (function
      | Error m -> Error (Network m)
      | Ok (status, body) ->
          Result.map_error
            (fun e ->
              match Gotrue.signup_disabled e with
              | true -> Not_allowed
              | false -> Server e)
            (Gotrue.decode_session ~now:sent ~status body))
    (post
       (Gotrue.id_token_grant ~base_url:Backend.supabase_url
          ~apikey:Backend.publishable_key ~id_token ~nonce:raw))

let map_error f fut = Fut.map (Result.map_error f) fut

let new_session t =
  let open Fut.Result_syntax in
  let* () = map_error (fun e -> Google e) (initialize t) in
  let* raw = Fut.return (random_hex 32) in
  let* hashed = sha256_hex raw in
  let* id_token =
    map_error
      (fun e ->
        match Cap_social_login.cancelled e with
        | true -> Cancelled
        | false -> Google e)
      (Cap_social_login.login_google ~nonce:hashed)
  in
  exchange ~raw ~id_token

(* A session made but not kept is logged out, so that no live refresh token
   is left on the server with nobody holding it. *)
let keep t ~attempt (s : Session.t) =
  match t.sign_in_attempt = attempt with
  | false ->
      logout_server s;
      Fut.return (Error Replaced)
  | true ->
      Fut.map
        (function
          | Error e ->
              logout_server s;
              Error (Storage e)
          | Ok () ->
              let previous = session t in
              t.generation <- t.generation + 1;
              t.failed_refreshes <- 0;
              set_phase t (Ready (Some s));
              log ("signed in, " ^ expiry_line s);
              schedule t (Session.refresh_in ~now:(now ()) s);
              Option.iter logout_server previous;
              Ok ())
        (Cap_preferences.set ~key ~value:(Session.to_string s))

let sign_in t =
  match t.phase with
  | Off -> Fut.return (Error Not_configured)
  | Reading | Ready _ -> (
      t.sign_in_attempt <- t.sign_in_attempt + 1;
      let attempt = t.sign_in_attempt in
      let open Fut.Syntax in
      let* made = new_session t in
      match made with
      | Ok s -> serially t (fun () -> keep t ~attempt s)
      | Error e -> (
          match t.sign_in_attempt = attempt with
          | true -> Fut.return (Error e)
          | false -> Fut.return (Error Replaced)))

let sign_out t =
  match session t with
  | None -> Fut.return (Ok ())
  | Some s ->
      let open Fut.Syntax in
      let generation = t.generation in
      logout_server s;
      let* google = Cap_social_login.logout_google () in
      (match google with
      | Ok () -> ()
      | Error e -> warn ("google logout: " ^ Cap_error.to_string e));
      serially t (fun () ->
          match t.generation = generation with
          | false ->
              (* A sign-in landed meanwhile: its session stands. *)
              Fut.return (Ok ())
          | true ->
              let+ removed = Cap_preferences.remove ~key in
              Result.map
                (fun () ->
                  t.generation <- t.generation + 1;
                  t.failed_refreshes <- 0;
                  stop_timer t;
                  set_phase t (Ready None);
                  log "signed out")
                (Result.map_error (fun e -> Storage e) removed))
