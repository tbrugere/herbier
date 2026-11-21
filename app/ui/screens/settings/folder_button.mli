(** 4m « Dossier Drive », its own card under the « Où vont mes photos » radios,
    shown while the storage is Drive or originals wait on this phone
    ([visible]): one button, titled « Dossier Drive », whose detail is
    {!Herbier_ui_model.Drive_text.folder_button} of {!State.account}'s [drive]
    and {!App.drive_folder} (the folder's name and the account's email), with a
    chevron. A tap opens the « Dossier Drive » sheet
    ([Route.Modal Drive_folder], {!Settings.drive_sheet}), which changes the
    account and renames the folder (the first choice is made from the Drive
    radio; an install whose storage is Drive with no account makes it here,
    prompted by {!Herbier_ui_model.Drive_text.drive_prompt}). Disabled (a build
    without a Google web client id) it is [aria-disabled], inert, and shows its
    reason under the detail. Under the button,
    {!Herbier_ui_model.Drive_text.drive_prompt} of {!App.drive_access} and the
    {!App.upload_queue}'s pending count (hidden when [None]), with « Autoriser »
    ({!App.authorize_drive}) when it offers one. *)

type t = {el : Brr.El.t;  (** the card *) bindings : Rb.binding list}

val v : App.t -> visible:bool React.signal -> t
