(** The running app's state and its plain services: {!App}'s value, shared by
    {!Geocoding}, {!Reference_fetch} and {!Packs}. {!App} is the interface; the
    docs of each value are there. *)

module Db := Herbier_store_io.Db
module Plant_id := Herbier_domain.Ids.Plant_id
module Observation_id := Herbier_domain.Ids.Observation_id
module Places := Herbier_domain.Places
module Place_name := Herbier_geo.Place_name
module Communes := Herbier_geo.Communes
module Pack_rows := Herbier_store.Commune_packs
module Code := Communes.Code
module Drive_text := Herbier_ui_model.Drive_text

type geocode_run =
  | Idle
  | Geocoding
  | Geocoding_again (* a trigger came during the run: read the list again *)

(* A plant's running thumbnail sync, and whether another was asked for
   meanwhile. *)
type thumb_sync = Running | Rerun_requested
type pack = {code : Code.t; row : Pack_rows.t; usable : bool}

val equal_pack : pack -> pack -> bool

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
  uploads : Herbier_photos_io.Upload_queue.t;
  upload_watch : Rb.binding option ref;
      (* style: mutable because {!start_uploads} sets it once, after
         {!create}: the binding on « Envoyer seulement en Wi-Fi », held here so
         that it stays reachable (primer §5) for the app's lifetime. *)
  drive_last : Drive_text.access React.signal;
      (* the last Drive token outcome since the last sign-in *)
  set_drive_last : ?step:React.step -> Drive_text.access -> unit;
  drive_access : Drive_text.access React.signal;
      (* derived from {!State.account} and [drive_last]; held here so that it
         stays reachable for the app's lifetime *)
  upload_queue : Drive_text.queue React.signal;
  set_upload_queue : ?step:React.step -> Drive_text.queue -> unit;
  health : Herbier_photos_io.Health.t;
}

val log_error : string list -> unit
(** One console error: the parts joined by spaces. *)

val log : string list -> unit
(** One console log line: the parts joined by spaces. *)

val create :
  db:Db.t ->
  state:State.t ->
  theme:(Theme.t, Theme.error) result ->
  auth:Herbier_sync.Auth.t ->
  t

val db : t -> Db.t
val state : t -> State.t
val theme : t -> (Theme.t, Theme.error) result
val saved : t -> unit React.event
val auth : t -> Herbier_sync.Auth.t
val engine : t -> Herbier_sync.Engine.t
val keepalive : t -> Herbier_sync.Keepalive.t
val synced : t -> unit React.event

val changed : t -> unit
(** Fires {!saved} and sends the engine a local write. *)

val start_auth : t -> unit
val start_sync : t -> unit
val start_keepalive : t -> unit
val start_uploads : t -> unit
val upload_pending : t -> unit
val uploads : t -> Herbier_photos_io.Upload_queue.t
val drive_access : t -> Drive_text.access React.signal
val check_drive_access : t -> unit
val authorize_drive : t -> unit
val upload_queue : t -> Drive_text.queue React.signal
val send_now : t -> unit
val stop_drive_uploads : t -> (unit, Db.error) result Fut.t

val set_storage :
  t -> Herbier_domain.Photo.Original_target.t -> (unit, Db.error) result Fut.t

val health : t -> Herbier_photos_io.Health.t
val check_originals : t -> unit

val commit : t -> Herbier_store.Outbox.edit list -> (int, Db.error) result Fut.t
(** {!Db.edit}, then {!changed} once a commit appended an entry; no geocoding
    (that is {!Geocoding.save}). *)

val online : t -> bool
(** {!State.network}'s [online] now. *)

val save_photos :
  t ->
  observation:Herbier_domain.Observation.t ->
  Herbier_photos_io.Capture.shot list ->
  Herbier_photos_io.Capture.shot list Fut.t
