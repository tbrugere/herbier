(** Runs a {!Herbier_ui_model.Drive_sheet} machine against {!App}: the command
    runner shared by the « Dossier Drive » sheet ([purpose = Change]) and 4m's
    Drive radio ([purpose = Turn_on]). [Run_chooser] → {!App.choose_account};
    [Ask_token] → {!App.folder_token}; [Store_account] → {!App.store_account},
    [~turn_on] iff [purpose = Turn_on]; [Rename] → {!App.rename_folder}; [Close]
    → [on_close]. Each result is fed back from its future's callback. *)

type t

val create : App.t -> purpose:Herbier_ui_model.Drive_sheet.purpose -> t
(** [Drive_sheet.open_] with {!State.account}'s Drive email and
    {!App.drive_folder} read now. Nothing runs before {!run}. *)

val state : t -> Herbier_ui_model.Drive_sheet.t
(** The machine now. *)

val run :
  t ->
  on_change:(Herbier_ui_model.Drive_sheet.t -> unit) ->
  on_close:(Herbier_ui_model.Drive_sheet.t -> unit) ->
  unit
(** Runs the opening commands a microtask later (never inside the caller's
    update step, such as a screen's build). [on_change] gets every later state
    and [on_close] the machine once it closed (at most once), both from future
    callbacks or {!feed}, outside update steps. A second [run] does nothing. *)

val feed : t -> Herbier_ui_model.Drive_sheet.event -> unit
(** One event (a tap); ignored before {!run} and after {!release}. *)

val release : t -> unit
(** Every later result is ignored (a [Stored (Error _)] or [Renamed (Error _)]
    is logged: no screen shows it); [on_close] is not called. A store or a
    rename already running completes (its write is not cancelled). Idempotent.
*)
