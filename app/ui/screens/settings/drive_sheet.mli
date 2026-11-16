(** 4m « Dossier Drive » sheet (modal [#reglages/dossier-drive]): chooses the
    Drive account and the folder together, running
    {!Herbier_ui_model.Drive_sheet}. Top bar: ← (the machine's [Tap_close];
    Android back does the same through the route, the router closing a shown
    Picker first) and « Dossier Drive ». Then a sand card: the account line
    ({!Herbier_ui_model.Drive_sheet.account_line}) and the link
    ({!Herbier_ui_model.Drive_sheet.other_account_label}, [aria-disabled] while
    {!Herbier_ui_model.Drive_sheet.busy}); then the folder
    ({!Herbier_ui_model.Drive_sheet.folder_line}); « Parcourir mes dossiers »
    (shown with Picker, enabled per {!Herbier_ui_model.Drive_sheet.can_browse});
    « Par défaut » (shown per {!Herbier_ui_model.Drive_sheet.can_default}); the
    status line while something runs ([role="status"],
    {!Herbier_ui_model.Drive_sheet.status_line}), the Picker note, and the error
    ([role="alert"], {!Herbier_ui_model.Drive_text.pick_error_text}).
    [aria-busy] while busy.

    Opening runs {!Drive_flow} with [purpose = Change] (the machine's opening
    with {!State.account}'s Drive email, {!App.drive_folder} and
    {!App.picker_config}: with no account stored, the chooser at once); its
    [Close] → [Route.back]. Leaving the sheet releases the flow: a shown Picker
    is disposed ({!Herbier_bindings.Google_picker.dismiss}) and every later
    result ignored. *)

val v : App.t -> Screen.t
