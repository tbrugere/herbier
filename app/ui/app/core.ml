module Db = Herbier_store_io.Db
module Plant_id = Herbier_domain.Ids.Plant_id
module Observation_id = Herbier_domain.Ids.Observation_id
module Places = Herbier_domain.Places
module Place_name = Herbier_geo.Place_name
module Communes = Herbier_geo.Communes
module Commune_packs = Herbier_geo_io.Commune_packs
module Pack_rows = Herbier_store.Commune_packs
module Code = Communes.Code
module Drive_text = Herbier_ui_model.Drive_text
module Identify_settings = Herbier_ui_model.Identify_settings
module Upload_queue = Herbier_photos_io.Upload_queue
module Health = Herbier_photos_io.Health

type geocode_run =
  | Idle
  | Geocoding
  | Geocoding_again (* a trigger came during the run: read the list again *)

(* A plant's running thumbnail sync, and whether another was asked for
   meanwhile. *)
type thumb_sync = Running | Rerun_requested

(* The session's flora list (Identification): not asked yet (or the last
   request failed), the request in flight (shared by concurrent callers), or
   the list received. *)
type flora_list =
  | Not_asked
  | Asking of
      ( Herbier_identify.Plantnet.project list,
        Herbier_identify.Plantnet.error )
      result
      Herbier_identify.logged
      Fut.t
  | Received of Herbier_identify.Plantnet.project list

type pack = {code : Code.t; row : Pack_rows.t; usable : bool} [@@deriving eq]
type pack_error = Busy | Offline | Pack of Herbier_geo_io.Commune_packs.error

type france =
  | France_idle
  | France_starting
  | France_running of {
      step : pack_error Herbier_geo.France_packs.step;
      cancelling : bool;
    }
  | France_finished of pack_error Herbier_geo.France_packs.outcome
  | France_deleting

type t = {
  db : Db.t;
  state : State.t;
  theme : (Theme.t, Theme.error) result;
  auth : Herbier_sync.Auth.t;
  engine : Herbier_sync.Engine.t;
  keepalive : Herbier_sync.Keepalive.t;
  saved : unit React.event;
  send_saved : unit -> unit;
  synced : unit React.event;
  generations : (Plant_id.t * int) list ref;
      (* style: mutable because a fetch's saves are checked against the
         plant's current generation when each branch ends, outside any
         reaction; nothing outside this module sees it. *)
  running : (Plant_id.t * int) list ref;
      (* style: mutable for the same reason: a fetch settles in a future's
         callback, outside any reaction. The fetches started and not settled
         or superseded, by generation; [fetching] is set from it. *)
  fetching : Plant_id.t list React.signal;
  set_fetching : Plant_id.t list -> unit;
  geocode_tried : (Observation_id.t * Places.point) list ref;
      (* style: mutable because a geocode run settles in a future's
         callback, outside any reaction; nothing outside this module sees
         it. The observations not to try again this session, with the
         position they were tried at (a moved one is tried again). *)
  geocode_run : geocode_run ref;
      (* style: mutable for the same reason: whether a run is going, and
         whether a trigger came during it. *)
  place_stored : Place_name.sources ref;
      (* style: mutable because a switch's write settles in a future's
         callback: the switches as last written to the settings table, what
         a failed write falls back to. *)
  place_writes : int ref;
  place_latest : (Place_name.source * int) list ref;
      (* style: mutable for the same reason: a write counter and the latest
         write per source; only the latest one's failure is shown. *)
  place_error : string option React.signal;
  set_place_error : string option -> unit;
  place_error_source : Place_name.source option ref;
      (* style: mutable for the same reason: the source whose failure
         {!place_error} shows, so another source's success keeps it. *)
  thumbs : (Plant_id.t * thumb_sync) list ref;
      (* style: mutable for the same reason: a thumbnail sync settles in a
         future's callback. The plants with a sync running. *)
  freeing : bool ref;
      (* style: mutable for the same reason: « Libérer » settles in a
         future's callback; thumbnail syncs asked meanwhile are skipped. *)
  communes : Communes.t ref;
      (* style: mutable because the packs load and download in futures'
         callbacks; a geocode run reads it at each observation. *)
  communes_loaded : unit Fut.t;
      (* the startup load of the packs: a geocode run waits for it, so an
         observation saved meanwhile is not skipped past the offline source *)
  packs : pack list React.signal;
  set_packs : ?step:React.step -> pack list -> unit;
  downloading : Communes.departement option React.signal;
  set_downloading : ?step:React.step -> Communes.departement option -> unit;
  france : france React.signal;
  set_france : ?step:React.step -> france -> unit;
  france_cancel : bool ref;
      (* style: mutable because the run reads it from futures' callbacks
         between départements: whether a cancel was asked. *)
  france_wake : (unit -> unit) option ref;
      (* style: mutable for the same reason: the sleeping retry's wake-up,
         called by a cancel so that it ends at once. *)
  uploads : Herbier_photos_io.Upload_queue.t;
  upload_watch : Rb.binding option ref;
      (* style: mutable because {!start_uploads} sets it once, after
         {!create}: the binding on « Envoyer seulement en Wi-Fi », held here so
         that it stays reachable (primer §5) for the app's lifetime. *)
  drive_last : Drive_text.access React.signal;
  set_drive_last : ?step:React.step -> Drive_text.access -> unit;
  drive_access : Drive_text.access React.signal;
  upload_queue : Drive_text.queue React.signal;
  set_upload_queue : ?step:React.step -> Drive_text.queue -> unit;
  drive_folder : Drive_text.folder React.signal;
  set_drive_folder : ?step:React.step -> Drive_text.folder -> unit;
  health : Health.t;
  floras : flora_list ref;
      (* style: mutable because a flora request settles in a future's
         callback. *)
  plantnet_key : Identify_settings.key React.signal;
  set_plantnet_key : ?step:React.step -> Identify_settings.key -> unit;
  key_writes : Herbier_sync.Serial.t;
  identify_on_photo : bool React.signal;
  set_identify_on_photo : ?step:React.step -> bool -> unit;
  plantnet_flora : Herbier_store.Settings.flora option React.signal;
  set_plantnet_flora :
    ?step:React.step -> Herbier_store.Settings.flora option -> unit;
  on_photo_writes : int ref;
  flora_writes : int ref;
  on_photo_stored : bool ref;
  flora_stored : Herbier_store.Settings.flora option ref;
      (* style: mutable because a write settles in a future's callback: a
         counter per setting, and the value last confirmed in SQLite, what a
         failed write falls back to. *)
  identify_gate : Identify_settings.gate React.signal;
  identify_gate_anchor : Rb.anchor;
}

let log_error parts = Brr.Console.(error [str (String.concat " " parts)])

(* The packs' load, started once by [create]: its result fills the index and
   [packs]; a failure leaves them empty. *)
let load_packs db ~communes ~set_packs =
  let started = Brr.Performance.now_ms Brr.G.performance in
  Fut.map
    (function
      | Error e -> log_error ["communes:"; Commune_packs.error_to_string e]
      | Ok (l : Commune_packs.loaded) ->
          communes := l.index;
          (* With every département's pack this is the app's slowest
             startup step: logged to measure it on the phone. *)
          Brr.Console.(
            log
              [
                str
                  (Printf.sprintf "communes: loaded %d %.0f ms"
                     (List.length l.rows)
                     (Brr.Performance.now_ms Brr.G.performance -. started));
              ]);
          set_packs
            (List.map
               (fun (code, row) ->
                 {
                   code;
                   row;
                   usable = not (List.exists (Code.equal code) l.unreadable);
                 })
               l.rows))
    (Commune_packs.load db)

(* The engine calls [on_cycle] from a future's callback, never inside an
   update step. A pull that wrote rows fires [saved] so screens reload, but
   is no local write: it must not trigger another cycle. *)
let on_cycle ~send_saved ~send_synced
    (report : Herbier_sync_core.Cycle.Report.t) =
  (match Herbier_sync_core.Cycle.Report.pulled_writes report with
  | true -> send_saved ()
  | false -> ());
  send_synced ()

(* [changed] runs from its own reaction on the result, so a subscriber that
   raises cannot keep the caller's future from being determined. *)
let commit_edits ~db ~changed edits =
  let r = Db.edit db edits in
  Fut.await r (function Ok 0 | Error _ -> () | Ok _ -> changed ());
  r

let denial : Herbier_sync.Auth.drive_error -> Drive_text.denial = function
  | Drive_unconfigured -> Unconfigured
  | Drive_no_account -> No_drive_account
  | Consent_needed -> Consent_needed
  | Consent_refused -> Consent_refused
  | Drive_offline -> Offline
  | Drive_misconfigured -> Misconfigured
  | No_google_account -> No_account
  | Drive_google _ -> Failed

(* Read at each call, so that the upload queue's and the health check's
   silent tokens follow an account change without being rebuilt. *)
let drive_account state = (React.S.value (State.account state)).drive

(* The two values name one account (Text.same_email), or neither names
   one. *)
let same_drive_account (a : Herbier_sync_core.Auth.Drive_account.t)
    (b : Herbier_sync_core.Auth.Drive_account.t) =
  match
    ( Herbier_sync_core.Auth.Drive_account.email a,
      Herbier_sync_core.Auth.Drive_account.email b )
  with
  | Some a, Some b -> Herbier_domain.Text.same_email a b
  | None, None -> true
  | Some (_ : string), None | None, Some (_ : string) -> false

(* Every Drive token the app asks for the stored account goes through here,
   so that its outcome is what 4m and 4e show. A token that resolves after the
   account changed is not recorded: its outcome was the old account's. The
   setter runs in the token's future callback, outside any update step. *)
let recorded_drive_token auth state ~set_last ~interactive =
  let account = drive_account state in
  Fut.map
    (fun result ->
      (match same_drive_account account (drive_account state) with
      | true ->
          set_last
            (match result with
            | Ok (_ : string) -> Drive_text.Granted
            | Error e -> Denied (denial e))
      | false -> ());
      result)
    (Herbier_sync.Auth.drive_token auth ~account ~interactive)

let create ~db ~state ~theme ~auth
    ~(identification : Identify_settings.settings) =
  let saved, send = React.E.create () in
  let synced, send_synced = React.E.create () in
  let send_saved () = send () in
  let keepalive = Herbier_sync.Keepalive.create ~db in
  let engine =
    Herbier_sync.Engine.create ~db ~auth ~keepalive
      ~on_cycle:(on_cycle ~send_saved ~send_synced:(fun () -> send_synced ()))
  in
  let packs, set_packs = React.S.create ~eq:(List.equal equal_pack) [] in
  let set_packs ?step p = set_packs ?step p in
  let downloading, set_downloading =
    React.S.create ~eq:(Option.equal Communes.equal_departement) None
  in
  let set_downloading ?step d = set_downloading ?step d in
  let france, set_france = React.S.create ~eq:( == ) France_idle in
  let set_france ?step f = set_france ?step f in
  let communes = ref Communes.empty in
  let drive_last, set_drive_last =
    React.S.create ~eq:Drive_text.equal_access Drive_text.Unknown
  in
  let set_drive_last ?step a = set_drive_last ?step a in
  let drive_access =
    React.S.l2 ~eq:Drive_text.equal_access
      (fun (a : State.account) last -> Drive_text.access ~drive:a.drive ~last)
      (State.account state) drive_last
  in
  let upload_queue, set_upload_queue =
    React.S.create ~eq:Drive_text.equal_queue Drive_text.empty_queue
  in
  let set_upload_queue ?step q = set_upload_queue ?step q in
  let drive_folder, set_drive_folder =
    React.S.create ~eq:Drive_text.equal_folder Drive_text.Default
  in
  let set_drive_folder ?step f = set_drive_folder ?step f in
  let commit =
    commit_edits ~db ~changed:(fun () ->
        send_saved ();
        Herbier_sync.Engine.local_write engine)
  in
  let token ~interactive =
    Fut.map
      (Result.map_error Herbier_sync.Auth.drive_error_to_string)
      (recorded_drive_token auth state
         ~set_last:(fun a -> set_drive_last a)
         ~interactive)
  in
  let drop_token = Herbier_sync.Auth.drop_drive_token auth in
  let uploads =
    Upload_queue.create ~db ~commit ~token ~drop_token ~wifi_only:(fun () ->
        (React.S.value (State.account state)).wifi_only)
  in
  (* Silent: a background check never shows the consent screen. *)
  let health =
    Health.create ~db ~commit
      ~token:(fun () -> token ~interactive:false)
      ~drop_token
  in
  let fetching, set_fetching =
    React.S.create ~eq:(List.equal Plant_id.equal) []
  in
  let place_error, set_place_error =
    React.S.create ~eq:(Option.equal String.equal) None
  in
  let plantnet_key, set_plantnet_key =
    React.S.create ~eq:Identify_settings.equal_key Identify_settings.Loading
  in
  let identify_on_photo, set_identify_on_photo =
    React.S.create ~eq:Bool.equal identification.on_photo
  in
  let plantnet_flora, set_plantnet_flora =
    React.S.create
      ~eq:(Option.equal Herbier_store.Settings.equal_flora)
      identification.flora
  in
  let identify_gate =
    React.S.l2 ~eq:Identify_settings.equal_gate
      (fun key (n : State.network) ->
        Identify_settings.gate key ~online:n.online)
      plantnet_key (State.network state)
  in
  {
    db;
    state;
    theme;
    auth;
    engine;
    keepalive;
    saved;
    send_saved;
    synced;
    generations = ref [];
    running = ref [];
    fetching;
    set_fetching = (fun ids -> set_fetching ids);
    geocode_tried = ref [];
    geocode_run = ref Idle;
    place_stored = ref (React.S.value (State.place_sources state));
    place_writes = ref 0;
    place_latest = ref [];
    place_error;
    set_place_error = (fun e -> set_place_error e);
    place_error_source = ref None;
    thumbs = ref [];
    freeing = ref false;
    communes;
    communes_loaded = load_packs db ~communes ~set_packs:(fun p -> set_packs p);
    packs;
    set_packs;
    downloading;
    set_downloading;
    france;
    set_france;
    france_cancel = ref false;
    france_wake = ref None;
    uploads;
    upload_watch = ref None;
    drive_last;
    set_drive_last;
    drive_access;
    upload_queue;
    set_upload_queue;
    drive_folder;
    set_drive_folder;
    health;
    floras = ref Not_asked;
    plantnet_key;
    set_plantnet_key = (fun ?step k -> set_plantnet_key ?step k);
    key_writes = Herbier_sync.Serial.create ();
    identify_on_photo;
    set_identify_on_photo = (fun ?step v -> set_identify_on_photo ?step v);
    plantnet_flora;
    set_plantnet_flora = (fun ?step f -> set_plantnet_flora ?step f);
    on_photo_writes = ref 0;
    flora_writes = ref 0;
    on_photo_stored = ref identification.on_photo;
    flora_stored = ref identification.flora;
    identify_gate;
    identify_gate_anchor = Rb.anchor identify_gate;
  }

let db t = t.db
let state t = t.state
let theme t = t.theme
let saved t = t.saved
let auth t = t.auth
let engine t = t.engine
let keepalive t = t.keepalive
let synced t = t.synced
let uploads t = t.uploads
let drive_access t = t.drive_access
let upload_queue t = t.upload_queue
let drive_folder t = t.drive_folder
let health t = t.health

let changed t =
  t.send_saved ();
  Herbier_sync.Engine.local_write t.engine

let log parts = Brr.Console.(log [str (String.concat " " parts)])
let online t = (React.S.value (State.network t.state)).online

let job_running : Herbier_bindings.Cap_uploader.job option -> bool = function
  | Some {state = Running; _} -> true
  | Some {state = Enqueued | Blocked | Succeeded _ | Failed _ | Cancelled; _}
  | None ->
      false

let last_upload t =
  Fut.map
    (function
      | Ok last -> last
      | Error e ->
          log_error ["upload: last upload:"; Db.error_to_string e];
          None)
    (Db.find t.db (Herbier_store.Settings.get Last_upload_at))

(* Called from futures' callbacks, outside any update step. *)
let refresh_queue t =
  let open Fut.Syntax in
  let* entries = Upload_queue.entries t.uploads in
  let+ last_upload = last_upload t in
  match entries with
  | Error e -> log_error ["upload: queue:"; Db.error_to_string e]
  | Ok entries ->
      let q =
        Drive_text.queue_of ~last_upload
          (List.map
             (fun (e : Upload_queue.entry) ->
               {
                 Drive_text.photo_id = e.row.photo_id;
                 state = e.photo;
                 running = job_running e.job;
               })
             entries)
      in
      t.set_upload_queue q

let refresh_folder t =
  Fut.map
    (function
      | Ok (root, picked) ->
          t.set_drive_folder (Drive_text.folder ~root ~picked)
      | Error e -> log_error ["drive: folder:"; Db.error_to_string e])
    (Herbier_photos_io.Drive_root.read_choice t.db)

let after_pass t pass =
  Fut.await
    (Fut.bind pass (fun () ->
         Fut.bind (refresh_queue t) (fun () -> refresh_folder t)))
    Fun.id

let upload_pending t =
  after_pass t (Upload_queue.run t.uploads ~interactive:false)

let send_now t = after_pass t (Upload_queue.send_now t.uploads)

let stop_drive_uploads t =
  let open Fut.Syntax in
  let* stopped = Upload_queue.stop_drive t.uploads in
  let+ () = refresh_queue t in
  stopped

let drive_token t ~interactive =
  recorded_drive_token t.auth t.state
    ~set_last:(fun a -> t.set_drive_last a)
    ~interactive

let stored_email t =
  Herbier_sync_core.Auth.Drive_account.email (drive_account t.state)

(* A token for an account not stored yet (the 4m sheet's new choice) says
   nothing about the stored one: only the stored account's is recorded. *)
let drive_token_for t ~email ~interactive =
  match Herbier_photos.Drive.same_account ~stored:(stored_email t) email with
  | true -> drive_token t ~interactive
  | false ->
      Herbier_sync.Auth.drive_token t.auth
        ~account:(Chosen {email = String.trim email})
        ~interactive

(* A new account forgets the last token outcome (it was the old account's),
   in the same step as the account itself. The same account keeps the
   spelling State and the setting already have. *)
let set_drive_account t (drive : Herbier_sync_core.Auth.Drive_account.t) =
  match same_drive_account drive (drive_account t.state) with
  | true -> ()
  | false ->
      let account = React.S.value (State.account t.state) in
      let step = React.Step.create () in
      State.set_account t.state ~step {account with drive};
      t.set_drive_last ~step Drive_text.Unknown;
      React.Step.execute step

let drive_chosen t =
  match drive_account t.state with
  | Chosen _ -> true
  | Unconfigured | Unchosen -> false

(* Photos may still wait for Drive with the storage App_only (« Les envoyer
   quand même »): they need the access too. *)
let check_drive_access t =
  let needed =
    match (React.S.value (State.account t.state)).storage with
    | Drive -> true
    | App_only -> Drive_text.pending_count (React.S.value t.upload_queue) > 0
  in
  match (drive_chosen t, needed) with
  | true, true ->
      Fut.await (drive_token t ~interactive:false)
        (fun (_ : (string, Herbier_sync.Auth.drive_error) result) -> ())
  | true, false | false, (true | false) -> ()

let authorize_drive t =
  Fut.await (drive_token t ~interactive:true) (function
    | Ok (_ : string) -> upload_pending t
    | Error (_ : Herbier_sync.Auth.drive_error) -> ())

(* No Drive account chosen, no token can come: the choice runs it. *)
let check_originals t =
  match (online t, drive_chosen t) with
  | true, true ->
      Fut.await (Health.run t.health ~force:false) (fun (_ : Health.outcome) ->
          ())
  | true, false | false, (true | false) -> ()

let storage_written t (target : Herbier_domain.Photo.Original_target.t) =
  let account = React.S.value (State.account t.state) in
  State.set_account t.state {account with storage = target};
  match target with Drive -> check_drive_access t | App_only -> ()

let set_storage t (target : Herbier_domain.Photo.Original_target.t) =
  Fut.map
    (function
      | Error e ->
          log_error ["réglages: storage"; Db.error_to_string e];
          Error e
      | Ok (_ : int) ->
          storage_written t target;
          Ok ())
    (Db.write t.db (Herbier_store.Settings.set Storage_target target))

(* An install that used Drive before it had its own account kept the folder
   ids of the signed-in account its tokens then named: that account is
   stored, once, so they are kept (Drive_root.seed). The write waits for the
   pass running, as the sheet's. *)
let seed_drive_account t ~email =
  match drive_account t.state with
  | Chosen _ | Unconfigured -> Fut.return ()
  | Unchosen ->
      Fut.map
        (function
          | Ok (Some email) -> set_drive_account t (Chosen {email})
          | Ok None -> ()
          | Error e -> log_error ["drive: account:"; Db.error_to_string e])
        (Upload_queue.exclusive t.uploads
           ~on_raise:(fun (_ : string) -> Ok None)
           (fun () ->
             Herbier_photos_io.Drive_root.seed t.db ~session_email:email))

(* Auth calls [on_change] from future and listener callbacks, never inside an
   update step, so the setter may run here. Drive's last token outcome is the
   Drive account's, not the session's: a sign-in or sign-out keeps it, except
   a sign-in that seeds the first account. *)
let start_auth t =
  Herbier_sync.Auth.start t.auth ~on_change:(fun status ->
      let account = React.S.value (State.account t.state) in
      State.set_account t.state {account with auth = status};
      match status with
      | Signed_in {email} ->
          Herbier_sync.Engine.signed_in t.engine;
          Fut.await (seed_drive_account t ~email) (fun () ->
              upload_pending t;
              check_drive_access t;
              check_originals t)
      | Unconfigured | Restoring | Signed_out -> ())

let start_sync t = Herbier_sync.Engine.start t.engine

(* Auth calls the hook from future callbacks; Keepalive logs every
   failure. *)
let start_keepalive t =
  let module K = Herbier_sync.Keepalive in
  let ignore_result (_ : (unit, K.error) result) = () in
  Herbier_sync.Auth.on_job_session t.auth (function
    | Dropped -> Fut.await (K.drop_session t.keepalive) ignore_result
    | Granted s -> Fut.await (K.replace_session t.keepalive s) ignore_result)

let log_listener what = function
  | Ok (_ : _) -> ()
  | Error e ->
      log_error ["upload:"; what; Herbier_bindings.Cap_error.to_string e]

(* Every trigger calls from a listener or a microtask, outside any update
   step. The listeners live as long as the app: their handles are not kept. *)
let start_uploads t =
  let module Q = Herbier_photos_io.Upload_queue in
  Fut.await (refresh_queue t) Fun.id;
  Fut.await (refresh_folder t) Fun.id;
  upload_pending t;
  check_originals t;
  Fut.await
    (Herbier_bindings.Cap_app.on_state_change (function
      | Active ->
          upload_pending t;
          check_originals t
      | Inactive -> ()))
    (log_listener "resume listener");
  Fut.await
    (Herbier_bindings.Cap_uploader.on_change (fun () -> upload_pending t))
    (log_listener "job listener");
  let wifi_only =
    React.S.map ~eq:Bool.equal
      (fun (a : State.account) -> a.wifi_only)
      (State.account t.state)
  in
  t.upload_watch :=
    Some
      (Rb.act (React.S.changes wifi_only) (fun (_ : bool) ->
           after_pass t (Q.wifi_changed t.uploads)))

(* [commit] does not geocode: the geocoder's own writes and the reference
   branches use it; the upload queue gets the same through [commit_edits]. *)
let commit t edits = commit_edits ~db:t.db ~changed:(fun () -> changed t) edits

let keep_original t (photo : Herbier_domain.Photo.t) original =
  let module Q = Herbier_photos_io.Upload_queue in
  Fut.map
    (function
      | Ok Q.Kept -> true
      | Ok Q.Not_drive -> false
      | Error e ->
          Log.error "photo" (Q.keep_error_to_string e);
          false)
    (Q.keep t.uploads photo original)

type saving = {
  any_saved : bool;
  any_kept : bool;
  failed : Herbier_photos_io.Capture.shot list;
}

let save_photos t ~(observation : Herbier_domain.Observation.t) shots =
  let target = (React.S.value (State.account t.state)).storage in
  let one (s : Herbier_photos_io.Capture.shot) =
    Herbier_photos_io.Preview.save t.db ~preview:s.preview
      ~observation_id:observation.id
      ~taken_at:(Option.value s.exif.taken_at ~default:(Ptime_clock.now ()))
      ~original_target:target s.original
  in
  let step acc (s : Herbier_photos_io.Capture.shot) =
    let open Fut.Syntax in
    let* saved = one s in
    match saved with
    | Ok photo ->
        let+ kept = keep_original t photo s.original in
        {acc with any_saved = true; any_kept = acc.any_kept || kept}
    | Error e ->
        Log.error "photo" (Herbier_photos_io.Preview.error_to_string e);
        Fut.return {acc with failed = s :: acc.failed}
  in
  Fut.map
    (fun {any_saved; any_kept; failed} ->
      if any_saved then changed t;
      (* The first Drive photo may need the drive.file consent (architecture
         §5, requested lazily): this pass may show it. *)
      if any_kept then
        after_pass t (Upload_queue.run t.uploads ~interactive:true);
      List.rev failed)
    (List.fold_left
       (fun acc s -> Fut.bind acc (fun r -> step r s))
       (Fut.return {any_saved = false; any_kept = false; failed = []})
       shots)
