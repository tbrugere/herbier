module Session = Herbier_sync_core.Auth.Session
module Gotrue = Herbier_sync_core.Auth.Gotrue
module Server = Server
module Cap_error = Herbier_bindings.Cap_error
module Cap_preferences = Herbier_bindings.Cap_preferences
module Cap_social_login = Herbier_bindings.Cap_social_login
module Cap_app = Herbier_bindings.Cap_app
module Web_crypto = Herbier_bindings.Web_crypto
module Fut_result = Herbier_bindings.Fut_result
module Lifecycle = Herbier_sync_core.Auth.Lifecycle

type status = Lifecycle.status =
  | Unconfigured
  | Restoring
  | Signed_out
  | Signed_in of {email : string option}

let equal_status = Lifecycle.equal_status

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

type job_session = Granted of Session.t | Dropped

(* style: mutable fields because the lifecycle, its timer and the flights in
   progress change from future, timer and app-state callbacks, outside any
   reaction; nothing outside this module sees them. *)
type t = {
  mutable life : Lifecycle.t;
  mutable on_change : (status -> unit) option; (* [None]: not started *)
  mutable refreshing : (Session.t, error) result Fut.t option;
      (* The refresh in flight: callers share it (single flight). *)
  mutable timer : Brr.G.timer_id option;
  mutable initialized : (unit, Cap_error.t) result Fut.t option;
      (* The plugin's initialisation, once per process; cleared on failure. *)
  writes : Serial.t;
  mutable on_job_session : (job_session -> unit) option;
  drive : Drive_access.t;
}

let log = Console_line.log Auth
let warn = Console_line.warn Auth
let console_error = Console_line.error Auth

module Stored = struct
  let key = "auth.session"
  let read () = Cap_preferences.get ~key
  let write s = Cap_preferences.set ~key ~value:(Session.to_string s)
  let remove () = Cap_preferences.remove ~key

  let remove_logged () =
    Fut.map
      (function
        | Ok () -> ()
        | Error e ->
            console_error ("session not removed: " ^ Cap_error.to_string e))
      (remove ())
end

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
    life = Lifecycle.create ~configured;
    on_change = None;
    refreshing = None;
    timer = None;
    initialized = None;
    writes = Serial.create ();
    on_job_session = None;
    drive = Drive_access.create ();
  }

let on_job_session t f = t.on_job_session <- Some f
let status t = Lifecycle.status t.life
let session t = Lifecycle.session t.life

let session_expires_at t =
  Option.map (fun (s : Session.t) -> s.expires_at) (session t)

let stale t ~generation = Lifecycle.stale t.life ~generation
let now () = Ptime_clock.now ()

(* Every write of the Preferences key runs here, after the previous one has
   resolved, together with the in-memory change that goes with it: a write
   never lands after a later one, and each step sees what the earlier steps
   did. *)
let serially t step = Serial.run t.writes step

(* A grant's failure as an [error]: [server_error] classifies GoTrue's answer
   when it is not a session. *)
let of_server ~server_error = function
  | Server.Network m -> Network m
  | Rejected e -> server_error e

let stop_timer t =
  Option.iter Brr.G.stop_timer t.timer;
  t.timer <- None

let ms_of span =
  let ms = Ptime.Span.to_float_s span *. 1000. in
  Float.to_int (Float.max 0. (Float.min ms 1e9))

let logout_server s =
  Fut.await (Server.logout s) (function
    | Ok () -> ()
    | Error e -> warn ("server logout: " ^ Server.error_to_string e))

(* The next state, then its actions in order: an action that calls back into
   this module (on_change, the job hook) sees the state it belongs to. *)
let rec apply t (life, actions) =
  t.life <- life;
  List.iter (run t) actions

and run t = function
  | Lifecycle.Notify status -> Option.iter (fun f -> f status) t.on_change
  | Reschedule -> (
      match session t with
      | Some s -> arm t (Session.refresh_in ~now:(now ()) s)
      | None -> stop_timer t)
  | Retry_in span -> arm t span
  | Stop_timer -> stop_timer t
  | Start_refresh -> Fut.await (refresh t) ignore
  | Log m -> log m
  | Warn m -> warn m
  | Console_error m -> console_error m
  | Logout_server s -> logout_server s
  | Job_dropped -> Option.iter (fun f -> f Dropped) t.on_job_session
  | Forget_stored {generation} ->
      Fut.await
        (serially t (fun () ->
             match stale t ~generation with
             | true -> Fut.return ()
             | false -> Stored.remove_logged ()))
        ignore

and arm t span =
  stop_timer t;
  match Lifecycle.armed t.life with
  | false -> ()
  | true ->
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
  let generation = Lifecycle.generation t.life in
  Fut.bind (Server.refresh s) (fun answer ->
      serially t (fun () -> refreshed t ~generation answer))

and refreshed t ~generation answer =
  let open Fut.Syntax in
  match (stale t ~generation, answer) with
  | true, _ -> (
      (* A sign-in or sign-out happened meanwhile: its session stands. *)
      match session t with
      | Some current -> Fut.return (Ok current)
      | None -> Fut.return (Error No_session))
  | false, Fresh fresh ->
      let+ stored = Stored.write fresh in
      let not_stored =
        match stored with
        | Ok () -> None
        | Error e -> Some (Cap_error.to_string e)
      in
      apply t (Lifecycle.refreshed t.life fresh ~not_stored);
      Ok fresh
  | false, Revoked e ->
      apply t (Lifecycle.revoked t.life e);
      let+ () = Stored.remove_logged () in
      Error No_session
  | false, Failed e ->
      let e = of_server ~server_error:(fun e -> Server e) e in
      apply t (Lifecycle.refresh_failed t.life ~why:(error_to_string e));
      Fut.return (Error e)

let resume t = apply t (Lifecycle.resumed ~now:(now ()) t.life)
let pause t = apply t (Lifecycle.paused t.life)
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
let debug_expire t = apply t (Lifecycle.expiry_moved ~now:(now ()) t.life)

let restore t =
  let generation = Lifecycle.generation t.life in
  Fut.map
    (fun stored ->
      apply t
        (Lifecycle.restored t.life ~generation
           (Result.map_error Cap_error.to_string stored)))
    (Stored.read ())

let start t ~on_change =
  match (t.on_change, Lifecycle.configured t.life) with
  | Some _, _ -> ()
  | None, false ->
      (* Stored, never called: an [Unconfigured] status never changes. *)
      t.on_change <- Some on_change
  | None, true ->
      t.on_change <- Some on_change;
      Fut.await (restore t) (fun () ->
          Fut.await
            (Cap_app.on_state_change (fun s -> on_state s t))
            (function
              | Ok (_ : Cap_app.listener) -> ()
              | Error e -> warn ("app state listener: " ^ Cap_error.to_string e));
          match Lifecycle.foreground t.life with
          | true -> resume t
          | false -> ())

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

let exchange ~raw_nonce ~id_token =
  Fut_result.map_error
    (of_server ~server_error:(fun e ->
         match Gotrue.signup_disabled e with
         | true -> Not_allowed
         | false -> Server e))
    (Server.id_token_grant ~raw_nonce ~id_token)

(* The id token and the raw nonce come back with the session: the
   keep-alive job's own session is a second grant of the same pair. *)
type made = {raw_nonce : string; id_token : string; session : Session.t}

let new_session t =
  let open Fut.Result_syntax in
  let* () = Fut_result.map_error (fun e -> Google e) (initialize t) in
  let crypto r =
    Result.map_error (fun m -> Crypto m) (Result.map Herbier_net.Hex.encode r)
  in
  let* raw = Fut.return (crypto (Web_crypto.random_bytes 32)) in
  let* hashed = Fut.map crypto (Web_crypto.sha256 raw) in
  let* id_token =
    Fut_result.map_error
      (fun e ->
        match Cap_social_login.cancelled e with
        | true -> Cancelled
        | false -> Google e)
      (Cap_social_login.login_google ~nonce:hashed)
  in
  let+ session = exchange ~raw_nonce:raw ~id_token in
  {raw_nonce = raw; id_token; session}

(* A session made but not kept is logged out, so that no live refresh token
   is left on the server with nobody holding it. *)
let keep t ~attempt (s : Session.t) =
  match Lifecycle.current t.life ~attempt with
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
              apply t (Lifecycle.kept t.life s);
              Ok ())
        (Stored.write s)

(* A second session, not the app's: two holders of one rotating refresh
   token would revoke each other. Another sign-in, a sign-out or a revoke
   meanwhile moves [attempt] or [generation]: the grant is then stale. *)
let grant_job_session t ~attempt ~generation {raw_nonce; id_token; _} =
  Fut.await (exchange ~raw_nonce ~id_token) (fun made ->
      let current =
        Lifecycle.current t.life ~attempt && not (stale t ~generation)
      in
      match (current, made) with
      | false, Ok s -> logout_server s
      | false, Error _ -> ()
      | true, Ok s -> (
          match t.on_job_session with
          | Some f ->
              log "job session granted";
              f (Granted s)
          | None -> logout_server s (* nobody to hand it to *))
      | true, Error e ->
          warn ("job session not granted: " ^ error_to_string e);
          run t Job_dropped)

let started t =
  let life, attempt = Lifecycle.sign_in_started t.life in
  t.life <- life;
  attempt

let sign_in t =
  match Lifecycle.configured t.life with
  | false -> Fut.return (Error Not_configured)
  | true -> (
      let attempt = started t in
      let open Fut.Syntax in
      let* made = new_session t in
      match made with
      | Ok made ->
          let+ kept = serially t (fun () -> keep t ~attempt made.session) in
          (match kept with
          | Ok () ->
              grant_job_session t ~attempt
                ~generation:(Lifecycle.generation t.life)
                made
          | Error _ -> ());
          kept
      | Error e -> (
          match Lifecycle.current t.life ~attempt with
          | true -> Fut.return (Error e)
          | false -> Fut.return (Error Replaced)))

let sign_out t =
  match session t with
  | None -> Fut.return (Ok ())
  | Some s ->
      let open Fut.Syntax in
      let generation = Lifecycle.generation t.life in
      logout_server s;
      let* google = Cap_social_login.logout_google () in
      (match google with
      | Ok () -> ()
      | Error e -> warn ("google logout: " ^ Cap_error.to_string e));
      serially t (fun () ->
          match stale t ~generation with
          | true ->
              (* A sign-in landed meanwhile: its session stands. *)
              Fut.return (Ok ())
          | false ->
              let+ removed = Stored.remove () in
              Result.map
                (fun () -> apply t (Lifecycle.signed_out t.life))
                (Result.map_error (fun e -> Storage e) removed))

let debug_import t text =
  match Lifecycle.configured t.life with
  | false -> Fut.return (Error Not_configured)
  | true -> (
      match Gotrue.decode_session ~now:(now ()) ~status:200 text with
      | Error e -> Fut.return (Error (Server e))
      | Ok s ->
          let attempt = started t in
          serially t (fun () -> keep t ~attempt s))

type drive_error = Drive_access.error =
  | Drive_unconfigured
  | Drive_no_account
  | Consent_needed
  | Consent_refused
  | Drive_offline
  | Drive_misconfigured
  | No_google_account
  | Drive_google of Cap_error.t

let equal_drive_error = Drive_access.equal_error
let drive_error_to_string = Drive_access.error_to_string
let drive_configured = Drive_access.configured

let drive_token t ~account ~interactive =
  Drive_access.token t.drive account ~interactive

let choose_drive_account = Drive_access.choose
let drop_drive_token (_ : t) token = Drive_access.drop token
