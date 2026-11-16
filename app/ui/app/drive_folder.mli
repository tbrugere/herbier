(** 4m « Dossier Drive » sheet's services: the Drive account and the folder
    originals go into, picked with Google Picker or the app's « Herbier »
    (architecture §5). Documented in {!App}. *)

module Drive_text := Herbier_ui_model.Drive_text

val picker_config : Drive_text.picker_config

val choose_account :
  unit ->
  (string, Herbier_sync_core.Auth.Drive_account.choose_error) result Fut.t

val folder_token :
  Core.t -> email:string -> (string, Drive_text.denial) result Fut.t

val open_picker :
  Core.t ->
  Herbier_bindings.Google_picker.ticket ->
  account:string ->
  token:string ->
  (Herbier_bindings.Google_picker.outcome, Drive_text.pick_error) result Fut.t

val store_pick :
  Core.t ->
  account:string ->
  Herbier_store.Settings.drive_folder ->
  (unit, Drive_text.pick_error) result Fut.t

val store_default :
  Core.t -> account:string -> (unit, Drive_text.pick_error) result Fut.t

val forget_account : Core.t -> (unit, Herbier_store_io.Db.error) result Fut.t
