(** 4m « Dossier Drive », its own card under the « Où vont mes photos » radios,
    shown only while the storage is Drive:
    {!Herbier_ui_model.Drive_text.folder_row} of {!App.picker_config},
    {!App.drive_access} and {!App.drive_folder}. « Choisir »
    ({!App.choose_drive_folder}) is [aria-disabled] when the row says so or a
    pick or reset runs, and [aria-busy] while it runs; « Par défaut »
    ({!App.default_drive_folder}) is shown when a picked folder is in force, and
    [aria-disabled] and inert while a pick or reset runs. A [Disabled] reason is
    one muted line under the detail; the last pick's or reset's error
    ({!Herbier_ui_model.Drive_text.pick_error_text}; a cancel shows nothing, and
    the next tap clears it) is a [role="alert"] line under the row. Android back
    while the Picker is shown closes it (the router asks
    {!Herbier_bindings.Google_picker.dismiss_if_shown}); leaving the screen
    cancels a pick still waiting for its token or for Picker, and disposes a
    Picker still shown ({!Herbier_bindings.Google_picker.dismiss}). *)

type t = {el : Brr.El.t;  (** the card *) bindings : Rb.binding list}

val v : App.t -> visible:bool React.signal -> t
