(** 4m « Dossier Drive » sheet and 4m's Drive radio: chooses the Drive account
    and renames the app's root folder (architecture §5, "Drive account"). A pure
    machine: the screen runs the {!command}s and feeds back the {!event}s. The
    folder is the app's own: it is created at the first upload or by a rename.

    With [purpose = Turn_on] (the radio) the only store command ever emitted is
    [Store_account], and only from [Authorizing] on [Token (Ok _)]; every other
    end is [[Close]] with nothing stored. The runner sets the storage to Drive
    with a [Turn_on] store, never with a [Change] one. *)

(** Why the machine runs: the « Dossier Drive » sheet ([Change]: the account
    line and the folder name, with their controls), or the 4m Drive radio
    ([Turn_on]: a straight line chooser → token → store of the account and the
    storage, no controls; any other end closes with nothing stored, the storage
    unchanged). *)
type purpose = Change | Turn_on [@@deriving eq, show]

(** What the sheet is doing, with the account it works with. *)
type phase =
  | Choosing of {previous : string option}
      (** the account chooser is showing; [previous]: the sheet's account before
          it, kept when the choice is cancelled *)
  | Authorizing of string
      (** an interactive drive.file token for that account is asked (the
          consent) *)
  | Storing of string
      (** that account (with [Turn_on]: and the storage) is written *)
  | Renaming of {account : string; name : string}
      (** the root folder is renamed [name] with [account]'s token *)
  | Idle of string option
      (** nothing runs: the sheet's own controls; [None] when no account was
          chosen yet *)
  | Closed  (** the sheet is gone; later events are ignored *)
[@@deriving eq, show]

type t = {
  purpose : purpose;
  stored : string option;
      (** the Drive account in settings: read at open, updated when a
          [Store_account] succeeds *)
  folder : string;
      (** the folder name shown: read at open, updated when a rename succeeds *)
  phase : phase;
  error : Drive_text.sheet_error option;
      (** [Change]: shown under the sheet's controls, cleared by the next tap
          acted on. [Turn_on]: the stored account's refusal while the chooser
          runs after it, and the error the flow closed on, for the screen to
          show under the radios. *)
}
[@@deriving eq, show]

type command =
  | Run_chooser
  | Ask_token of string  (** interactive, for that email *)
  | Store_account of string
      (** [App.store_account]; with [purpose = Turn_on], the storage set to
          Drive in the same write *)
  | Rename of {account : string; name : string}  (** [App.rename_folder] *)
  | Close
      (** the flow ends: [Change] → [Route.back]; [Turn_on] → the screen shows
          [error], if any *)
[@@deriving eq, show]

(** The printers show a Drive access token as [<token>]. *)
type event =
  | Tap_other_account
  | Tap_rename of string  (** the name field's text, raw *)
  | Tap_close
  | Chosen of string
  | Choose_failed of Herbier_sync_core.Auth.Drive_account.choose_error
  | Token of (string, Drive_text.denial) result
  | Stored of (unit, Drive_text.sheet_error) result
  | Renamed of (string, Drive_text.sheet_error) result
      (** [Ok n]: the name Drive now has *)
[@@deriving eq, show]

val account : t -> string option
(** The account the sheet works with: the phase's ([Choosing]'s [previous]);
    [Closed] → [None]. *)

val open_ :
  purpose:purpose -> stored:string option -> folder:string -> t * command list
(** [error = None]; [stored] trimmed, [folder] kept verbatim.
    - [Change]: [stored = None] (or blank) → [Choosing {previous = None}],
      [[Run_chooser]]; [Some e] → [Idle (Some (trim e))], [[]] (no token at
      open: only a rename needs one).
    - [Turn_on]: [stored = None] (or blank) → [Choosing {previous = None}],
      [[Run_chooser]]; [Some e] → [Authorizing (trim e)],
      [[Ask_token (trim e)]]. *)

val step : t -> event -> t * command list
(** [purpose = Change], first rule that applies; "stored" below means the same
    address as [t.stored] ({!Herbier_domain.Text.same_email}). [error] is
    cleared by every [Tap_*] acted on.
    - [Closed], any event → unchanged, [[]].
    - Any other phase, [Tap_close] → [Closed], [[Close]]. A store or a rename
      already running completes; its result is then ignored.
    - [Choosing], [Chosen e] → [Authorizing (trim e)], [[Ask_token (trim e)]];
      [e] blank → [Idle previous], [error = Some Chooser_failed].
    - [Choosing {previous = None}], [Choose_failed Cancelled] → [Closed],
      [[Close]] (the first choice was cancelled: nothing changed).
    - [Choosing {previous = Some _}], [Choose_failed Cancelled] →
      [Idle previous], [[]].
    - [Choosing], [Choose_failed No_google_account] → [Idle previous],
      [error = Some Chooser_no_account]; [Choose_failed Choose_failed] →
      [Idle previous], [error = Some Chooser_failed].
    - [Authorizing a], [Token (Ok _)]: [a] stored → [Idle (Some a)], [[]]
      (nothing changes); else → [Storing a], [[Store_account a]].
    - [Authorizing a], [Token (Error d)], [a] stored → [Idle (Some a)],
      [error = Some (Token d)]; [a] not stored → back to the stored account:
      [Idle t.stored], [error = Some (Other_account d)] ([Some (Token d)] when
      nothing is stored).
    - [Storing a], [Stored (Ok ())] → [Idle (Some a)], [stored = Some a], [[]]
      (the sheet stays open).
    - [Storing _], [Stored (Error e)] → [Idle t.stored], [error = Some e].
    - [Idle a], [Tap_other_account] → [Choosing {previous = a}],
      [[Run_chooser]].
    - [Idle (Some a)], [Tap_rename s]: [s] blank → [error = Some Blank_name],
      [[]]; else → [Renaming {account = a; name = trim s}], even when
      [trim s = folder] (the name shown may be stale; Drive's answer brings its
      own back), [[Rename {account = a; name = trim s}]].
    - [Renaming {account; _}], [Renamed (Ok n)] → [Idle (Some account)],
      [folder = n], [[]].
    - [Renaming {account; _}], [Renamed (Error e)] → [Idle (Some account)],
      [error = Some e] ([folder] unchanged).
    - Every other (phase, event) pair: unchanged, [[]] (a late or stray result,
      a tap while something runs, [Tap_rename] with no account).

    [purpose = Turn_on], first rule that applies (every close is [[Close]];
    [t.stored] never changes):
    - [Closed], any event → unchanged, [[]].
    - Any other phase, [Tap_close] → [Closed], [error = None].
    - [Tap_other_account], [Tap_rename _] → unchanged, [[]] (no controls in this
      purpose; never a [Rename]).
    - [Choosing _], [Chosen e] → [Authorizing (trim e)], [[Ask_token (trim e)]];
      [e] blank → [Closed], [error = Some Chooser_failed].
    - [Choosing _], [Choose_failed Cancelled] → [Closed], [error] kept ([None],
      or the stored account's refusal that opened the chooser).
    - [Choosing _], [Choose_failed No_google_account] → [Closed],
      [error = Some Chooser_no_account]; [Choose_failed Choose_failed] →
      [Closed], [error = Some Chooser_failed].
    - [Authorizing a], [Token (Ok _)] → [Storing a], [[Store_account a]] (also
      for the stored account: the storage must be written).
    - [Authorizing a], [Token (Error d)], [a] stored and [error = None] →
      [Choosing {previous = None}], [error = Some (Token d)], [[Run_chooser]]
      (the radio's only way to another account: the « Dossier Drive » sheet is
      hidden under [App_only]); else → [Closed], [error = Some (Token d)].
    - [Storing _], [Stored (Ok ())] → [Closed], [error = None];
      [Stored (Error e)] → [Closed], [error = Some e].
    - Every other (phase, event) pair: unchanged, [[]]. *)

val account_line : t -> string
(** « Compte : <email> » / « Aucun compte choisi ». *)

val other_account_label : t -> string
(** « Utiliser un autre compte » when {!account} is [Some _], else « Choisir un
    compte ». *)

val can_rename : t -> bool
(** [purpose = Change] and [Idle (Some _)]. *)

val busy : t -> bool
(** [Choosing | Authorizing | Storing | Renaming]. *)

val status_line : t -> string option
(** What runs, while the sheet's controls are inert: [Authorizing] → « Connexion
    à Google Drive… »; [Storing] → « Enregistrement… »; [Renaming] → « Renommage
    du dossier… »; else [None] ([Choosing] shows the system's chooser). *)
