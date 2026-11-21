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
module Identify_settings := Herbier_ui_model.Identify_settings

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

type pack = {code : Code.t; row : Pack_rows.t; usable : bool}
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
      (* the last Drive token outcome since the last Drive account change *)
  set_drive_last : ?step:React.step -> Drive_text.access -> unit;
  drive_access : Drive_text.access React.signal;
      (* derived from {!State.account} and [drive_last]; held here so that it
         stays reachable for the app's lifetime *)
  upload_queue : Drive_text.queue React.signal;
  set_upload_queue : ?step:React.step -> Drive_text.queue -> unit;
  drive_folder : string React.signal;
  set_drive_folder : ?step:React.step -> string -> unit;
  health : Herbier_photos_io.Health.t;
  floras : flora_list ref;
      (* style: mutable because a flora request settles in a future's
         callback. *)
  plantnet_key : Identify_settings.key React.signal; (* starts [Loading] *)
  set_plantnet_key : ?step:React.step -> Identify_settings.key -> unit;
  key_writes : Herbier_sync.Serial.t;
      (* the key's Preferences reads and writes, one after another *)
  identify_on_photo : bool React.signal;
  set_identify_on_photo : ?step:React.step -> bool -> unit;
  plantnet_flora : Herbier_store.Settings.flora option React.signal;
  set_plantnet_flora :
    ?step:React.step -> Herbier_store.Settings.flora option -> unit;
  on_photo_writes : int ref;
  flora_writes : int ref;
  on_photo_stored : bool ref;
  flora_stored : Herbier_store.Settings.flora option ref;
      (* style: mutable because a write settles in a future's callback: the
         writes started so far and the value last confirmed in SQLite, per
         setting. Only the latest write's failure reverts the signal, to the
         confirmed value. *)
  identify_gate : Identify_settings.gate React.signal;
      (* {!Identify_settings.gate} of [plantnet_key] and {!State.network} *)
  identify_gate_anchor : Rb.anchor;
      (* keeps [identify_gate] updating for the app's lifetime: a screen's
          released binding would otherwise stop it ({!Rb.release}) *)
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
  identification:Identify_settings.settings ->
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
(** [Auth.start]; each status into {!State.account}. On [Signed_in {email}]: the
    engine is told, then, with no Drive account stored yet,
    [Drive_root.seed ~session_email:email] inside [Upload_queue.exclusive] (an
    older install's folders are kept for the account its tokens named; a seeded
    account goes into State as {!set_drive_account} does), then
    [upload_pending], [check_drive_access] and [check_originals]. *)

val start_sync : t -> unit
val start_keepalive : t -> unit
val start_uploads : t -> unit
val upload_pending : t -> unit
val uploads : t -> Herbier_photos_io.Upload_queue.t
val drive_access : t -> Drive_text.access React.signal
val check_drive_access : t -> unit
val authorize_drive : t -> unit
val upload_queue : t -> Drive_text.queue React.signal
val drive_folder : t -> string React.signal

val refresh_folder : t -> unit Fut.t
(** Reads [Drive_root.root]'s name (the stored one, else « Herbier ») into
    {!drive_folder}; a read error is a console line and keeps the last value.
    Also run after every pass (with the {!upload_queue} read): a pass may store
    the name Drive gave the root. *)

val drive_token :
  t -> interactive:bool -> (string, Herbier_sync.Auth.drive_error) result Fut.t
(** [Auth.drive_token] for {!State.account}'s [drive], read at the call; its
    outcome recorded into {!drive_access}, unless the account changed meanwhile
    (the outcome was the old account's). *)

val drive_token_for :
  t ->
  email:string ->
  interactive:bool ->
  (string, Herbier_sync.Auth.drive_error) result Fut.t
(** The token for [email], which may not be the stored account yet (4m's sheet):
    the stored account ([Drive.same_account]) → {!drive_token}; another →
    [Auth.drive_token] for [Chosen {email = trim email}], not recorded. *)

val set_drive_account : t -> Herbier_sync_core.Auth.Drive_account.t -> unit
(** After the setting was written: when the email changes (trim and ASCII case
    ignored), {!State.account}'s [drive] := that and the last Drive token
    outcome is reset to [Unknown], in one update step; the same account changes
    nothing (State keeps the spelling the setting has). Call it outside any
    update step. *)

val denial : Herbier_sync.Auth.drive_error -> Drive_text.denial
(** The mapping {!drive_access} documents. *)

val send_now : t -> unit
val stop_drive_uploads : t -> (unit, Db.error) result Fut.t

val set_storage :
  t -> Herbier_domain.Photo.Original_target.t -> (unit, Db.error) result Fut.t

val storage_written : t -> Herbier_domain.Photo.Original_target.t -> unit
(** After [Storage_target] was written (by {!set_storage}, or with a pick from
    4m's Drive radio): {!State.account}'s [storage] := target; [Drive] also runs
    {!check_drive_access}. Call it outside any update step. *)

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
