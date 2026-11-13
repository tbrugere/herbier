(* Before [open Brr], whose own Uri would shadow it. *)
module Http_uri = Uri
open Brr
module Sync = Herbier_sync
module Tag = Herbier_domain.Tag

(* The transport, logging what it sends: the request line is what the page
   checks, and only Client.Make knows it. *)
module Logged = struct
  include Sync.Net.Transport

  (* style: a mutable sink because Client.Make calls [send] with no context;
     set by the page before each request, dev builds only. *)
  let sink : (string -> unit) ref = ref ignore

  let send ~meth ~url ~headers ?body () =
    let query =
      match Http_uri.verbatim_query url with
      | None -> ""
      | Some q -> "?" ^ Http_uri.pct_decode q
    in
    !sink
      (Herbier_bindings.Timed_fetch.meth_to_string meth
      ^ " "
      ^ Http_uri.path url
      ^ query);
    send ~meth ~url ~headers ?body ()
end

module Remote = Sync.Net.Rest.Make (Logged)

let append log text = El.append_children log [El.div [El.txt' text]]
let button label = El.button ~at:[At.type' (Jstr.v "button")] [El.txt' label]

let on_click el f =
  ignore (Ev.listen Ev.click (fun _ -> f ()) (El.as_target el) : Ev.listener)

let set_disabled el disabled =
  El.set_at At.Name.disabled
    (match disabled with true -> Some Jstr.empty | false -> None)
    el

let iso t = Ptime.to_rfc3339 ~frac_s:3 ~tz_offset_s:0 t

let conn_of app field =
  match String.trim (Jstr.to_string (El.prop El.Prop.value field)) with
  | "" ->
      Fut.map
        (Result.map_error Sync.Auth.error_to_string)
        (Sync.Net.Transport.conn (App.auth app))
  | token -> Fut.return (Ok (Sync.Net.Transport.conn_of_token token))

let throwaway_tag () =
  let now = Ptime_clock.now () in
  {
    Tag.id = Herbier_domain.Ids.Tag_id.fresh ();
    name = "dev-rest " ^ iso now;
    created_at = now;
    updated_at = now;
    deleted_at = Some now;
  }

let report log label = function
  | Ok detail -> append log (label ^ ": ok" ^ detail)
  | Error e -> append log (label ^ ": " ^ Remote.error_to_string e)

let upsert log conn =
  Logged.sink := append log;
  let tag = throwaway_tag () in
  Fut.map
    (fun r -> report log "upsert" (Result.map (fun () -> " · " ^ tag.name) r))
    (Remote.upsert conn Sync.Synced.tags tag)

let summary (tags : Tag.t list) =
  let last =
    List.fold_left
      (fun acc (t : Tag.t) ->
        match acc with
        | Some a when Ptime.is_later a ~than:t.updated_at -> acc
        | Some _ | None -> Some t.updated_at)
      None tags
  in
  Printf.sprintf " · %d rows, last updated_at %s" (List.length tags)
    (Option.fold ~none:"-" ~some:iso last)

let pull log conn =
  Logged.sink := append log;
  let open Fut.Syntax in
  let* all = Remote.select_since conn Sync.Synced.tags ~since:None ~page:0 in
  report log "select (since none)" (Result.map summary all);
  let since = Ptime.sub_span (Ptime_clock.now ()) (Ptime.Span.of_int_s 60) in
  let+ recent = Remote.select_since conn Sync.Synced.tags ~since ~page:0 in
  report log "select (since 1 min)" (Result.map summary recent)

(* The button stays disabled until its run ends, so a double tap does not
   start a second one. *)
let with_conn button log fut run =
  set_disabled button true;
  Fut.await fut (function
    | Error e ->
        append log ("conn: " ^ e);
        set_disabled button false
    | Ok conn -> Fut.await (run log conn) (fun () -> set_disabled button false))

let page app =
  let log = El.div ~at:[At.v (Jstr.v "role") (Jstr.v "log")] [] in
  let field =
    El.input
      ~at:
        [
          At.type' (Jstr.v "password");
          At.v (Jstr.v "autocomplete") (Jstr.v "off");
          At.v (Jstr.v "spellcheck") (Jstr.v "false");
          At.v (Jstr.v "autocapitalize") (Jstr.v "off");
          At.v (Jstr.v "aria-label") (Jstr.v "Jeton");
          At.v (Jstr.v "placeholder") (Jstr.v "Jeton (vide : session)");
        ]
      ()
  in
  let send = button "Envoyer une étiquette"
  and pull_button = button "Tirer les étiquettes"
  and invalid = button "Jeton invalide" in
  on_click send (fun () -> with_conn send log (conn_of app field) upsert);
  on_click pull_button (fun () ->
      with_conn pull_button log (conn_of app field) pull);
  on_click invalid (fun () ->
      with_conn invalid log
        (Fut.return (Ok (Sync.Net.Transport.conn_of_token "invalid")))
        upsert);
  El.div
    [
      El.h1 [El.txt' "REST check"];
      El.p [El.txt' ("url: " ^ Sync.Backend.supabase_url)];
      field;
      El.div [send; pull_button; invalid];
      log;
    ]

let el = function
  | Error e -> El.p [El.txt' ("no app: " ^ e)]
  | Ok app -> page app
