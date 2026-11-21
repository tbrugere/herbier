(** 4m's Drive radio, in « Où vont mes photos »:
    {!Herbier_ui_model.Drive_text.drive_option} of {!State.account} and
    {!App.drive_folder} as a {!Radio_row} (title « Google Drive », its detail,
    the chosen « <folder> · <email> » once the storage is Drive, and, when the
    option is [Disabled], [aria-disabled], inert, with its reason). A tap that
    {!Herbier_ui_model.Drive_text.drive_option_starts} runs {!Drive_flow} with
    [purpose = Turn_on] (the chooser when no Drive account is stored, or once
    when Drive refuses the stored one, then the account's drive.file token); the
    account and the storage are written together once the token is granted, so
    the radio, which reads [storage], never leaves the stored value: a cancel or
    an error changes nothing. No folder is chosen: the app's folder is created
    at the first upload or by a rename in « Dossier Drive ». While the flow
    runs, the radio is [aria-busy] and [status] says what runs
    ({!Herbier_ui_model.Drive_sheet.status_line}; empty otherwise). When it
    closes, [set_error] gets its {!Herbier_ui_model.Drive_text.sheet_error_text}
    ([None] for a store or a plain cancel; a cancel of the chooser opened after
    the stored account's refusal keeps that refusal); a start clears it.
    Released with the screen: a running flow is released
    ({!Drive_flow.release}). *)

type t = {
  radio : Brr.El.t;  (** for the radiogroup *)
  status : Brr.El.t;  (** a [role="status"] line, for under the radios *)
  bindings : Rb.binding list;
}

val v :
  App.t ->
  storage:Herbier_domain.Photo.Original_target.t React.signal ->
  set_error:(?step:React.step -> string option -> unit) ->
  t
