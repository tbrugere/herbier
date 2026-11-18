(** Pl@ntNet identification's state (architecture §12):
    [Identify_io = Herbier_identify.Make (Plantnet_transport)], one current
    request per caller, the session's flora list, the offline gate, the stored
    previews read and the console lines. Documented in {!App}. *)

type image = Preview of Brr.Blob.t | Stored of Herbier_domain.Ids.Photo_id.t
type channel

val channel : unit -> channel

type identify_error =
  | Identify_offline
  | Preview_unreadable of Herbier_domain.Ids.Photo_id.t
  | Plantnet of Herbier_identify.Plantnet.error

type 'a current = Settled of ('a, identify_error) result | Superseded

val flora_list_text : identify_error -> string

val identify :
  Core.t ->
  channel ->
  key:string ->
  flora:string ->
  ?no_reject:bool ->
  (image * Herbier_identify.Organ.sent) list ->
  Herbier_identify.identified current Fut.t

val floras :
  Core.t ->
  key:string ->
  (Herbier_identify.Plantnet.project list, identify_error) result Fut.t

val load_plantnet_key : Core.t -> unit Fut.t
val plantnet_key : Core.t -> Herbier_ui_model.Identify_settings.key React.signal

val set_plantnet_key :
  Core.t -> string -> (unit, Herbier_bindings.Cap_error.t) result Fut.t

val identify_on_photo : Core.t -> bool React.signal

val set_identify_on_photo :
  Core.t -> bool -> (unit, Herbier_store_io.Db.error) result Fut.t

val plantnet_flora : Core.t -> Herbier_store.Settings.flora option React.signal

val set_plantnet_flora :
  Core.t ->
  Herbier_store.Settings.flora option ->
  (unit, Herbier_store_io.Db.error) result Fut.t

val identify_gate :
  Core.t -> Herbier_ui_model.Identify_settings.gate React.signal
