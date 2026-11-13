open Brr
module Auth = Herbier_sync.Auth
module Backend = Herbier_sync.Backend

let prefix n s =
  match String.length s > n with true -> String.sub s 0 n ^ "…" | false -> s

let unset = function "" -> "(unset)" | s -> s

let backend_lines =
  [
    "url: " ^ unset Backend.supabase_url;
    "key: " ^ unset (prefix 16 Backend.publishable_key);
    (match Backend.google_web_client_id with
    | "" -> "google client id: unset"
    | id -> "google client id: set, " ^ prefix 12 id);
  ]

let status_to_string : Auth.status -> string = function
  | Unconfigured -> "Unconfigured"
  | Restoring -> "Restoring"
  | Signed_out -> "Signed_out"
  | Signed_in {email} ->
      "Signed_in " ^ Option.value email ~default:"(no address)"

let expiry = function
  | None -> "expires: -"
  | Some at ->
      let tz_offset_s =
        Herbier_bindings.Js_date.offset_at_s (Ptime.to_float_s at)
      in
      let left = Ptime.Span.to_float_s (Ptime.diff at (Ptime_clock.now ())) in
      Printf.sprintf "expires: %s (%.0f s left when shown)"
        (Ptime.to_rfc3339 ~tz_offset_s at)
        left

let report log label fut =
  Fut.await fut (function
    | Ok () -> Kit.append log (label ^ ": ok")
    | Error e -> Kit.append log (label ^ ": " ^ Auth.error_to_string e))

let page app =
  let auth = App.auth app in
  let status = El.p [] and expires = El.p [] in
  let render () =
    El.set_children status
      [El.txt' ("status: " ^ status_to_string (Auth.status auth))];
    El.set_children expires [El.txt' (expiry (Auth.session_expires_at auth))]
  in
  (* style: a local ref because the poll compares with what it last showed.
     It redraws only on a change, so that the page's text stays still between
     changes (scripts/emulator.sh waits for that). *)
  let state () =
    status_to_string (Auth.status auth)
    ^ Option.fold ~none:"" ~some:Ptime.to_rfc3339 (Auth.session_expires_at auth)
  in
  let shown = ref (state ()) in
  let poll () =
    let now = state () in
    match String.equal now !shown with
    | true -> ()
    | false ->
        shown := now;
        render ()
  in
  render ();
  let (_ : G.timer_id) = G.set_interval ~ms:1000 poll in
  let log = El.div ~at:[At.v (Jstr.v "role") (Jstr.v "log")] [] in
  let sign_in = Kit.button "Se connecter"
  and refresh = Kit.button "Rafraîchir maintenant"
  and expire = Kit.button "Expirer"
  and sign_out = Kit.button "Se déconnecter"
  and update = Kit.button "Actualiser" in
  Kit.on_click update render;
  Kit.on_click sign_in (fun () -> report log "sign_in" (Auth.sign_in auth));
  Kit.on_click refresh (fun () -> report log "refresh" (Auth.refresh_now auth));
  Kit.on_click expire (fun () ->
      Auth.debug_expire auth;
      render ();
      Kit.append log "expire: ok");
  Kit.on_click sign_out (fun () -> report log "sign_out" (Auth.sign_out auth));
  El.div
    (El.h1 [El.txt' "Auth check"]
     :: List.map (fun l -> El.p [El.txt' l]) backend_lines
    @ [
        status; expires; El.div [sign_in; refresh; expire; sign_out; update]; log;
      ])

let el = function
  | Error e -> El.p [El.txt' ("no app: " ^ e)]
  | Ok app -> page app
