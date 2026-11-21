(** 4m « Dossier Drive » sheet (modal [#reglages/dossier-drive]): the Drive
    account and the name of the app's folder, running
    {!Herbier_ui_model.Drive_sheet}. Top bar: ← (the machine's [Tap_close];
    Android back does the same through the route) and « Dossier Drive ». Then a
    sand card: the account line ({!Herbier_ui_model.Drive_sheet.account_line})
    and the link ({!Herbier_ui_model.Drive_sheet.other_account_label},
    [aria-disabled] while {!Herbier_ui_model.Drive_sheet.busy}); then the label
    « Nom du dossier » and a text field holding the machine's [folder] at open
    (placeholder « Herbier »), whose action « Renommer » and Enter feed
    [Tap_rename <the field's text>] when not busy (the action [aria-disabled]
    unless {!Herbier_ui_model.Drive_sheet.can_rename}); the field is set to the
    machine's [folder] when a rename changes it. Then the help line
    ({!Herbier_ui_model.Drive_text.folder_help}), the status line while
    something runs ([role="status"],
    {!Herbier_ui_model.Drive_sheet.status_line}) and the error ([role="alert"],
    {!Herbier_ui_model.Drive_text.sheet_error_text}). [aria-busy] while busy.

    Opening runs {!Drive_flow} with [purpose = Change] (the machine's opening
    with {!State.account}'s Drive email and {!App.drive_folder}: with no account
    stored, the chooser at once; else nothing runs, no token is asked until a
    rename); its [Close] → [Route.back]. Leaving the sheet releases the flow:
    every later result is ignored. *)

val v : App.t -> Screen.t
