(** 4m « Dossier Drive »: the folder originals go into, picked with Google
    Picker or the app's « Herbier » (architecture §5). Documented in {!App}. *)

val picker_config : Herbier_ui_model.Drive_text.picker_config

val choose_drive_folder :
  Core.t -> (unit, Herbier_ui_model.Drive_text.pick_error) result Fut.t

val default_drive_folder :
  Core.t -> (unit, Herbier_store_io.Db.error) result Fut.t
