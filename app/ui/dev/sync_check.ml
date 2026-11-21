open Brr
module Db = Herbier_store_io.Db
module Outbox = Herbier_store.Outbox
module Sync_state = Herbier_store.Sync_state
module Sync = Herbier_sync
module Sync_core = Herbier_sync_core
module Observation = Herbier_domain.Observation

let iso t = Ptime.to_rfc3339 ~frac_s:6 ~tz_offset_s:0 t

let entry_line (e : Outbox.entry) =
  Printf.sprintf "#%d %s %s: %s (attempts %d)" (Outbox.seq_to_int e.seq)
    e.table_name e.row_id
    (Option.value e.last_error ~default:"")
    e.attempts

let last_lines engine =
  match Sync.Engine.last engine with
  | None -> ["last cycle: none"]
  | Some r -> ("last cycle: " ^ iso r.started) :: Sync_core.Cycle.Report.lines r

let rejected_entry () =
  let now = Ptime_clock.now () in
  let o =
    {
      Observation.id = Herbier_domain.Ids.Observation_id.fresh ();
      plant_id = None;
      at = now;
      position = Some {lat = 45.; lon = 5.; accuracy_m = Some (-1.)};
      place_label = None;
      place_derived = None;
      place_detail = None;
      note = Some "dev-sync rejected entry";
      created_at = now;
      updated_at = now;
      deleted_at = None;
    }
  in
  Outbox.entry_stmt ~table_name:"observations"
    ~row_id:(Herbier_domain.Ids.Observation_id.to_string o.id)
    (Postgrest.Input.to_json (Herbier_store.Observations.input o))

let unreadable_entry () =
  Outbox.entry_stmt ~table_name:"nope"
    ~row_id:
      (Herbier_domain.Ids.Observation_id.to_string
         (Herbier_domain.Ids.Observation_id.fresh ()))
    (`Assoc [])

let lines_of el lines =
  El.set_children el (List.map (fun l -> El.div [El.txt' l]) lines)

let page app =
  let db = App.db app and engine = App.engine app and auth = App.auth app in
  let status = El.div [] and outbox = El.div [] and cursors = El.div [] in
  let engine_el = El.div [] in
  let log = El.div ~at:[At.v (Jstr.v "role") (Jstr.v "log")] [] in
  let render () =
    lines_of status
      ["status: " ^ Auth_check.status_to_string (Sync.Auth.status auth)];
    lines_of engine_el
      (("engine: "
       ^ Sync_core.Cycle.Schedule.state_to_string (Sync.Engine.state engine))
      :: last_lines engine);
    let open Fut.Syntax in
    let* count = Db.all db Outbox.count in
    let* parked = Db.all db Outbox.parked in
    let+ state = Db.all db Sync_state.all in
    (match (count, parked) with
    | Ok [n], Ok parked ->
        lines_of outbox
          (Printf.sprintf "outbox: %d, parked %d" n (List.length parked)
          :: List.map entry_line parked)
    | Ok _, Ok _ -> lines_of outbox ["outbox: unexpected count"]
    | Error e, _ | _, Error e ->
        lines_of outbox ["outbox: " ^ Db.error_to_string e]);
    match state with
    | Ok [] -> lines_of cursors ["cursors: none"]
    | Ok rows ->
        lines_of cursors
          ("cursors:" :: List.map (fun (table, at) -> table ^ " " ^ iso at) rows)
    | Error e -> lines_of cursors ["cursors: " ^ Db.error_to_string e]
  in
  let refresh () = Fut.await (render ()) Fun.id in
  let session =
    El.input
      ~at:
        [
          At.type' (Jstr.v "password");
          At.v (Jstr.v "placeholder") (Jstr.v "session JSON");
        ]
      ()
  in
  let import = Kit.button "Importer la session"
  and sync = Kit.button "Synchroniser"
  and reset = Kit.button "Curseurs à zéro"
  and rejected = Kit.button "Entrée refusée"
  and unreadable = Kit.button "Entrée illisible"
  and update = Kit.button "Actualiser" in
  let write ?(after = ignore) label stmt =
    Fut.await (Db.write db stmt) (function
      | Ok (_ : int) ->
          Kit.append log (label ^ ": ok");
          after ();
          refresh ()
      | Error e -> Kit.append log (label ^ ": " ^ Db.error_to_string e))
  in
  let entry label stmt =
    write label stmt ~after:(fun () -> Sync.Engine.local_write engine)
  in
  Kit.on_click import (fun () ->
      let text = Jstr.to_string (El.prop El.Prop.value session) in
      El.set_prop El.Prop.value Jstr.empty session;
      Fut.await (Sync.Auth.debug_import auth text) (function
        | Ok () ->
            Kit.append log "import: ok";
            refresh ()
        | Error e -> Kit.append log ("import: " ^ Sync.Auth.error_to_string e)));
  Kit.on_click sync (fun () ->
      Sync.Engine.sync_now engine;
      Kit.append log "sync: requested";
      refresh ());
  Kit.on_click reset (fun () -> write "reset" Sync_state.reset);
  Kit.on_click rejected (fun () -> entry "rejected entry" (rejected_entry ()));
  Kit.on_click unreadable (fun () ->
      entry "unreadable entry" (unreadable_entry ()));
  Kit.on_click update refresh;
  let el =
    El.div
      [
        El.h1 [El.txt' "Sync check"];
        status;
        El.div [session; import];
        engine_el;
        outbox;
        cursors;
        El.div [sync; reset; rejected; unreadable; update];
        log;
      ]
  in
  Rb.hold el [Rb.act (App.synced app) refresh];
  Fut.await (render ()) (fun () -> Kit.append log "done");
  el

let el = function
  | Error e -> El.p [El.txt' ("no app: " ^ e)]
  | Ok app -> page app
