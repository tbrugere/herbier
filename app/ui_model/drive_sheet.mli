(** 4m « Dossier Drive » sheet and 4m's Drive radio: chooses the Drive account
    and the folder together (architecture §5, "Drive account"). A pure machine:
    the screen runs the {!command}s and feeds back the {!event}s. Google Picker
    is Google's modal overlay, so the screen is underneath it: [Browsing] means
    the Picker is shown. Nothing is stored before a pick or « Par défaut »: the
    account chosen lives in the phase until then.

    With [purpose = Turn_on] (the radio) the only store command ever emitted is
    [Store_pick], and only from [Browsing] on [Picker_picked]; every other end
    is [[Close]] with nothing stored. The runner sets the storage to Drive with
    a [Turn_on] pick, never with a [Change] one. *)

(** Why the machine runs: the « Dossier Drive » sheet ([Change]: change the
    existing choice, its controls shown), or the 4m Drive radio ([Turn_on]: a
    straight line chooser → token → Picker → store, no controls; any end other
    than a stored pick closes with nothing stored, the storage unchanged). *)
type purpose = Change | Turn_on [@@deriving eq, show]

(** What the sheet is doing, with the account it works with. *)
type phase =
  | Choosing of {previous : string option}
      (** the account chooser is showing; [previous]: the sheet's account before
          it, kept when the choice is cancelled *)
  | Authorizing of string
      (** an interactive drive.file token for that account is asked *)
  | Browsing of string  (** Google Picker is shown for that account *)
  | Storing of string
      (** a pick (checked with files.get) or « Par défaut » for that account is
          stored *)
  | Idle of string option
      (** nothing runs: the sheet's own controls; [None] when no account was
          chosen yet *)
  | Closed  (** the sheet is gone; later events are ignored *)
[@@deriving eq, show]

type t = {
  purpose : purpose;
  stored : string option;  (** the Drive account in settings at open *)
  folder : Drive_text.folder;  (** the stored folder at open *)
  picker : Drive_text.picker_config;
  phase : phase;
  error : Drive_text.pick_error option;
      (** [Change]: shown under the sheet's controls, cleared by the next tap
          acted on. [Turn_on]: the stored account's refusal while the chooser
          runs after it, and the error the flow closed on, for the screen to
          show under the radios. *)
}
[@@deriving eq, show]

(** The printers show a Drive access token as [<token>]. *)
type command =
  | Run_chooser
  | Ask_token of string  (** interactive, for that email *)
  | Open_picker of {account : string; token : string}
  | Store_pick of {account : string; folder_id : string; folder_name : string}
      (** check the folder with files.get under [account]'s token, then
          [Drive_root.choose ~account]; with [purpose = Turn_on], the storage
          set to Drive in the same write *)
  | Store_default of string  (** [Drive_root.reset ~account] *)
  | Close
      (** the flow ends: [Change] → [Route.back]; [Turn_on] → the screen shows
          [error], if any *)
[@@deriving eq, show]

type event =
  | Tap_other_account
  | Tap_browse
  | Tap_default
  | Tap_close
  | Chosen of string
  | Choose_failed of Herbier_sync_core.Auth.Drive_account.choose_error
  | Token of (string, Drive_text.denial) result
  | Picker_picked of {id : string; name : string}
  | Picker_cancelled
  | Picker_failed of Drive_text.pick_error
      (** [Picker_unavailable] / [Offline] *)
  | Stored of (unit, Drive_text.pick_error) result
[@@deriving eq, show]

val account : t -> string option
(** The account the sheet works with: the phase's ([Choosing]'s [previous]);
    [Closed] → [None]. *)

val open_ :
  purpose:purpose ->
  stored:string option ->
  folder:Drive_text.folder ->
  picker:Drive_text.picker_config ->
  t * command list
(** [error = None] unless stated.
    - [Turn_on] with [Picker_unconfigured] → [Closed],
      [error = Some Picker_unavailable], [[Close]] (the radio is disabled in
      such a build; the machine's own guard: never a chooser or a token).
    - Else [stored = None] (or blank) → [Choosing {previous = None}],
      [[Run_chooser]]; [Some e] → [Authorizing (trim e)],
      [[Ask_token (trim e)]]. *)

val step : t -> event -> t * command list
(** [purpose = Change], first rule that applies; "stored" below means the same
    address as [stored] ({!Herbier_domain.Text.same_email}). [error] is cleared
    by every [Tap_*] acted on.
    - [Closed], any event → unchanged, [[]].
    - Any other phase, [Tap_close] → [Closed], [[Close]]. A store already
      running completes; its [Stored] is then ignored.
    - [Choosing], [Chosen e] → [Authorizing (trim e)], [[Ask_token (trim e)]];
      [e] blank → [Idle previous], [error = Some Chooser_failed].
    - [Choosing {previous = None}], [Choose_failed Cancelled] → [Closed],
      [[Close]] (the first choice was cancelled: nothing changed).
    - [Choosing {previous = Some _}], [Choose_failed Cancelled] →
      [Idle previous], [[]].
    - [Choosing], [Choose_failed No_google_account] → [Idle previous],
      [error = Some Chooser_no_account].
    - [Choosing], [Choose_failed Choose_failed] → [Idle previous],
      [error = Some Chooser_failed].
    - [Authorizing a], [Token (Ok tok)] with [Picker_ready] → [Browsing a],
      [[Open_picker {account = a; token = tok}]]; with [Picker_unconfigured] →
      [Idle (Some a)], [[]].
    - [Authorizing a], [Token (Error d)], [a] stored → [Idle (Some a)],
      [error = Some (Token d)]; [a] not stored → back to the stored account:
      [Idle stored], [error = Some (Other_account d)] ([Some (Token d)] when
      nothing is stored).
    - [Browsing a], [Picker_picked {id; name}] → [Storing a],
      [[Store_pick {account = a; folder_id = id; folder_name = name}]].
    - [Browsing a], [Picker_cancelled] → [Idle (Some a)], [[]].
    - [Browsing a], [Picker_failed e] → [Idle (Some a)], [error = Some e].
    - [Storing _], [Stored (Ok ())] → [Closed], [[Close]].
    - [Storing a], [Stored (Error e)] → [Idle (Some a)], [error = Some e].
    - [Idle a], [Tap_other_account] → [Choosing {previous = a}],
      [[Run_chooser]].
    - [Idle (Some a)], [Tap_browse] when {!can_browse} → [Authorizing a],
      [[Ask_token a]].
    - [Idle (Some a)], [Tap_default] when {!can_default} → [Storing a],
      [[Store_default a]].
    - Every other (phase, event) pair: unchanged, [[]] (a late or stray result,
      a tap while something runs).

    [purpose = Turn_on], first rule that applies (every close is [[Close]]):
    - [Closed], any event → unchanged, [[]].
    - Any other phase, [Tap_close] → [Closed], [error = None].
    - [Tap_other_account], [Tap_browse], [Tap_default] → unchanged, [[]] (no
      controls in this purpose; never a [Store_default]).
    - [Choosing _], [Chosen e] → [Authorizing (trim e)], [[Ask_token (trim e)]];
      [e] blank → [Closed], [error = Some Chooser_failed].
    - [Choosing _], [Choose_failed Cancelled] → [Closed], [error] kept ([None],
      or the stored account's refusal that opened the chooser).
    - [Choosing _], [Choose_failed No_google_account] → [Closed],
      [error = Some Chooser_no_account]; [Choose_failed Choose_failed] →
      [Closed], [error = Some Chooser_failed].
    - [Authorizing a], [Token (Ok tok)] with [Picker_ready] → [Browsing a],
      [[Open_picker {account = a; token = tok}]]; with [Picker_unconfigured] →
      [Closed], [error = Some Picker_unavailable].
    - [Authorizing a], [Token (Error d)], [a] stored and [error = None] →
      [Choosing {previous = None}], [error = Some (Token d)], [[Run_chooser]]
      (the radio's only way to another account: the « Dossier Drive » sheet is
      hidden under [App_only]); else → [Closed], [error = Some (Token d)]
      (nothing was stored, nothing to go back to).
    - [Browsing a], [Picker_picked {id; name}] → [Storing a],
      [[Store_pick {account = a; folder_id = id; folder_name = name}]].
    - [Browsing _], [Picker_cancelled] → [Closed], [error = None].
    - [Browsing _], [Picker_failed e] → [Closed], [error = Some e].
    - [Storing _], [Stored (Ok ())] → [Closed], [error = None];
      [Stored (Error e)] → [Closed], [error = Some e].
    - Every other (phase, event) pair: unchanged, [[]]. *)

val account_line : t -> string
(** « Compte : <email> » / « Aucun compte choisi ». *)

val other_account_label : t -> string
(** « Utiliser un autre compte » when {!account} is [Some _], else « Choisir un
    compte ». *)

val folder_line : t -> string option
(** Where originals go for {!account}: [None] without an account; the stored
    account with [Picked _] → « Dossier : <{!Drive_text.folder_name}> »; the
    stored account with [Default], or another account (whose « Herbier » a pick
    or the next upload makes) → « Dossier : {!Drive_text.app_folder} ». *)

val status_line : t -> string option
(** What runs, while the sheet's controls are inert: [Authorizing] → « Connexion
    à Google Drive… »; [Browsing] → « Ouverture de Google Drive… » (until
    Google's overlay covers the sheet); [Storing] → « Enregistrement… »; else
    [None] ([Choosing] shows the system's chooser). *)

val can_browse : t -> bool
(** [purpose = Change], [Idle (Some _)] and [Picker_ready]. *)

val can_default : t -> bool
(** [purpose = Change], [Idle (Some a)], and [a] is not the stored account or
    [folder <> Default]: « Par défaut » is offered when it changes something. *)

val busy : t -> bool
(** [Choosing | Authorizing | Browsing | Storing]. *)

val picker_note : t -> string option
(** [purpose = Change] and [Picker_unconfigured] → « Choix du dossier
    indisponible dans cette version : les photos vont dans « Herbier ». »; else
    [None]. *)

val picker_title : string -> string
(** The Picker's [setTitle] for that account: « Dossier Drive · <email> ». *)
