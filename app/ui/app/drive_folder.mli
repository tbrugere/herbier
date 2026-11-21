(** 4m « Dossier Drive » sheet's services: the Drive account and the name of the
    app's root folder (architecture §5). Documented in {!App}. *)

module Drive_text := Herbier_ui_model.Drive_text

val choose_account :
  unit ->
  (string, Herbier_sync_core.Auth.Drive_account.choose_error) result Fut.t

val folder_token :
  Core.t -> email:string -> (string, Drive_text.denial) result Fut.t

val store_account :
  Core.t ->
  account:string ->
  turn_on:bool ->
  (unit, Drive_text.sheet_error) result Fut.t

val rename_folder :
  Core.t ->
  account:string ->
  name:string ->
  (string, Drive_text.sheet_error) result Fut.t

val forget_account : Core.t -> (unit, Herbier_store_io.Db.error) result Fut.t
