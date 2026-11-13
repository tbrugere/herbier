module Db = Herbier_store_io.Db
module Plant_id = Herbier_domain.Ids.Plant_id
module Observation_id = Herbier_domain.Ids.Observation_id
module Places = Herbier_domain.Places
module Place_name = Herbier_geo.Place_name
module Communes = Herbier_geo.Communes
module Commune_packs = Herbier_geo_io.Commune_packs
module Pack_rows = Herbier_store.Commune_packs
module Code = Communes.Code

type geocode_run =
  | Idle
  | Geocoding
  | Geocoding_again (* a trigger came during the run: read the list again *)

(* A plant's running thumbnail sync, and whether another was asked for
   meanwhile. *)
type thumb_sync = Running | Rerun_requested
type pack = {code : Code.t; row : Pack_rows.t; usable : bool} [@@deriving eq]

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
}

let log_error parts = Brr.Console.(error [str (String.concat " " parts)])

(* The packs' load, started once by [create]: its result fills the index and
   [packs]; a failure leaves them empty. *)
let load_packs db ~communes ~set_packs =
  Fut.map
    (function
      | Error e -> log_error ["communes:"; Commune_packs.error_to_string e]
      | Ok (l : Commune_packs.loaded) ->
          communes := l.index;
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

let create ~db ~state ~theme ~auth =
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
  let communes = ref Communes.empty in
  let fetching, set_fetching =
    React.S.create ~eq:(List.equal Plant_id.equal) []
  in
  let place_error, set_place_error =
    React.S.create ~eq:(Option.equal String.equal) None
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
    communes;
    communes_loaded = load_packs db ~communes ~set_packs:(fun p -> set_packs p);
    packs;
    set_packs;
    downloading;
    set_downloading;
  }

let db t = t.db
let state t = t.state
let theme t = t.theme
let saved t = t.saved
let auth t = t.auth
let engine t = t.engine
let keepalive t = t.keepalive
let synced t = t.synced

let changed t =
  t.send_saved ();
  Herbier_sync.Engine.local_write t.engine

(* Auth calls [on_change] from future and listener callbacks, never inside an
   update step, so the setter may run here. *)
let start_auth t =
  Herbier_sync.Auth.start t.auth ~on_change:(fun status ->
      let account = React.S.value (State.account t.state) in
      State.set_account t.state {account with auth = status};
      match status with
      | Signed_in _ -> Herbier_sync.Engine.signed_in t.engine
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

(* [saved] fires from its own reaction on the result, so a subscriber that
   raises cannot keep the caller's future from being determined. [commit]
   does not geocode: the geocoder's own writes and the reference branches
   (no observation in them) use it. *)
let commit t edits =
  let r = Db.edit t.db edits in
  Fut.await r (function Ok 0 | Error _ -> () | Ok _ -> changed t);
  r

let log parts = Brr.Console.(log [str (String.concat " " parts)])
let online t = (React.S.value (State.network t.state)).online

let save_photos t ~(observation : Herbier_domain.Observation.t) shots =
  let target = (React.S.value (State.account t.state)).storage in
  let one (s : Herbier_photos_io.Capture.shot) =
    Herbier_photos_io.Preview.save t.db ~preview:s.preview
      ~observation_id:observation.id
      ~taken_at:(Option.value s.exif.taken_at ~default:(Ptime_clock.now ()))
      ~original_target:target s.original
  in
  let step (saved, failed) s =
    Fut.map
      (function
        | Ok (_ : Herbier_domain.Photo.t) -> (saved + 1, failed)
        | Error e ->
            Log.error "photo" (Herbier_photos_io.Preview.error_to_string e);
            (saved, s :: failed))
      (one s)
  in
  Fut.map
    (fun (saved, failed) ->
      (match saved with 0 -> () | _ -> changed t);
      List.rev failed)
    (List.fold_left
       (fun acc s -> Fut.bind acc (fun r -> step r s))
       (Fut.return (0, []))
       shots)
