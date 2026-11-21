module Drive_account = Herbier_sync_core.Auth.Drive_account

type purpose = Change | Turn_on [@@deriving eq, show]

type phase =
  | Choosing of {previous : string option}
  | Authorizing of string
  | Storing of string
  | Renaming of {account : string; name : string}
  | Idle of string option
  | Closed
[@@deriving eq, show]

type t = {
  purpose : purpose;
  stored : string option;
  folder : string;
  phase : phase;
  error : Drive_text.sheet_error option;
}
[@@deriving eq, show]

type command =
  | Run_chooser
  | Ask_token of string
  | Store_account of string
  | Rename of {account : string; name : string}
  | Close
[@@deriving eq, show]

let hidden_token fmt (_ : string) = Format.pp_print_string fmt "<token>"

type event =
  | Tap_other_account
  | Tap_rename of string
  | Tap_close
  | Chosen of string
  | Choose_failed of Drive_account.choose_error
  | Token of ((string[@printer hidden_token]), Drive_text.denial) result
  | Stored of (unit, Drive_text.sheet_error) result
  | Renamed of (string, Drive_text.sheet_error) result
[@@deriving eq, show]

let account t =
  match t.phase with
  | Choosing {previous} -> previous
  | Authorizing a | Storing a | Renaming {account = a; _} -> Some a
  | Idle a -> a
  | Closed -> None

let stored_account t a =
  match t.stored with
  | Some s -> Herbier_domain.Text.same_email s a
  | None -> false

let closed t error = ({t with phase = Closed; error}, [Close])
let authorize t a = ({t with phase = Authorizing a}, [Ask_token a])

let open_ ~purpose ~stored ~folder =
  let stored = Option.bind stored Herbier_domain.Text.non_blank in
  let base = {purpose; stored; folder; phase = Closed; error = None} in
  match (purpose, stored) with
  | (Change | Turn_on), None ->
      ({base with phase = Choosing {previous = None}}, [Run_chooser])
  | Change, Some e -> ({base with phase = Idle (Some e)}, [])
  | Turn_on, Some e -> authorize base e

let can_rename t =
  match (t.purpose, t.phase) with
  | Change, Idle (Some (_ : string)) -> true
  | Turn_on, (_ : phase)
  | ( Change,
      ( Idle None
      | Choosing _
      | Authorizing (_ : string)
      | Storing (_ : string)
      | Renaming _ | Closed ) ) ->
      false

let busy t =
  match t.phase with
  | Choosing _ | Authorizing (_ : string) | Storing (_ : string) | Renaming _ ->
      true
  | Idle (_ : string option) | Closed -> false

let failed t account e = ({t with phase = Idle account; error = Some e}, [])

(* A tap acted on clears the error. *)
let tapped t phase commands = ({t with phase; error = None}, commands)

(* The blank rule is Herbier_photos.Drive.folder_name's, which the app checks
   again before any request. A name equal to the one shown is still sent: that
   one may be stale after a rename in Drive, and the answer brings Drive's
   back. *)
let rename t a raw =
  match Herbier_domain.Text.non_blank raw with
  | None -> ({t with error = Some Blank_name}, [])
  | Some name ->
      tapped t (Renaming {account = a; name}) [Rename {account = a; name}]

let step_change t event =
  match (t.phase, event) with
  | Closed, (_ : event) -> (t, [])
  | (Choosing _ | Authorizing _ | Storing _ | Renaming _ | Idle _), Tap_close ->
      tapped t Closed [Close]
  | Choosing {previous}, Chosen e -> (
      match Herbier_domain.Text.non_blank e with
      | Some e -> authorize t e
      | None -> failed t previous Chooser_failed)
  | Choosing {previous = None}, Choose_failed Cancelled ->
      ({t with phase = Closed}, [Close])
  | Choosing {previous = Some _ as previous}, Choose_failed Cancelled ->
      ({t with phase = Idle previous}, [])
  | Choosing {previous}, Choose_failed No_google_account ->
      failed t previous Chooser_no_account
  | Choosing {previous}, Choose_failed Choose_failed ->
      failed t previous Chooser_failed
  | Authorizing a, Token (Ok (_ : string)) -> (
      match stored_account t a with
      | true -> ({t with phase = Idle (Some a)}, [])
      | false -> ({t with phase = Storing a}, [Store_account a]))
  (* A token refused for an account not stored yet: back to the stored one. *)
  | Authorizing a, Token (Error d) -> (
      match stored_account t a with
      | true -> failed t (Some a) (Token d)
      | false -> (
          match t.stored with
          | Some (_ : string) -> failed t t.stored (Other_account d)
          | None -> failed t None (Token d)))
  | Storing a, Stored (Ok ()) ->
      ({t with phase = Idle (Some a); stored = Some a}, [])
  | Storing (_ : string), Stored (Error e) -> failed t t.stored e
  | Idle previous, Tap_other_account ->
      tapped t (Choosing {previous}) [Run_chooser]
  | Idle (Some a), Tap_rename raw -> rename t a raw
  | Renaming {account; _}, Renamed (Ok name) ->
      ({t with phase = Idle (Some account); folder = name}, [])
  | Renaming {account; _}, Renamed (Error e) -> failed t (Some account) e
  | ( Choosing _,
      (Tap_other_account | Tap_rename _ | Token _ | Stored _ | Renamed _) )
  | ( Authorizing _,
      ( Tap_other_account | Tap_rename _ | Chosen _ | Choose_failed _ | Stored _
      | Renamed _ ) )
  | ( Storing _,
      ( Tap_other_account | Tap_rename _ | Chosen _ | Choose_failed _ | Token _
      | Renamed _ ) )
  | ( Renaming _,
      ( Tap_other_account | Tap_rename _ | Chosen _ | Choose_failed _ | Token _
      | Stored _ ) )
  | Idle None, Tap_rename _
  | Idle _, (Chosen _ | Choose_failed _ | Token _ | Stored _ | Renamed _) ->
      (t, [])

let step_turn_on t event =
  match (t.phase, event) with
  | Closed, (_ : event) -> (t, [])
  | (Choosing _ | Authorizing _ | Storing _ | Renaming _ | Idle _), Tap_close ->
      closed t None
  | Choosing _, Chosen e -> (
      match Herbier_domain.Text.non_blank e with
      | Some e -> authorize t e
      | None -> closed t (Some Chooser_failed))
  | Choosing _, Choose_failed Cancelled -> closed t t.error
  | Choosing _, Choose_failed No_google_account ->
      closed t (Some Chooser_no_account)
  | Choosing _, Choose_failed Choose_failed -> closed t (Some Chooser_failed)
  | Authorizing a, Token (Ok (_ : string)) ->
      ({t with phase = Storing a}, [Store_account a])
  (* The stored account refused (removed from the phone, consent withdrawn):
     the radio has no other way to « Utiliser un autre compte », so the
     chooser opens, once; the refusal is kept for a cancel to show. *)
  | Authorizing a, Token (Error d) -> (
      match (stored_account t a, t.error) with
      | true, None ->
          ( {t with phase = Choosing {previous = None}; error = Some (Token d)},
            [Run_chooser] )
      | true, Some (_ : Drive_text.sheet_error)
      | false, (None | Some (_ : Drive_text.sheet_error)) ->
          closed t (Some (Token d)))
  | Storing (_ : string), Stored (Ok ()) -> closed t None
  | Storing (_ : string), Stored (Error e) -> closed t (Some e)
  | ( (Choosing _ | Authorizing _ | Storing _ | Renaming _ | Idle _),
      (Tap_other_account | Tap_rename _) )
  | Choosing _, (Token _ | Stored _ | Renamed _)
  | Authorizing _, (Chosen _ | Choose_failed _ | Stored _ | Renamed _)
  | Storing _, (Chosen _ | Choose_failed _ | Token _ | Renamed _)
  | Renaming _, (Chosen _ | Choose_failed _ | Token _ | Stored _ | Renamed _)
  | Idle _, (Chosen _ | Choose_failed _ | Token _ | Stored _ | Renamed _) ->
      (t, [])

let step t event =
  match t.purpose with
  | Change -> step_change t event
  | Turn_on -> step_turn_on t event

let account_line t =
  match account t with
  | Some e -> "Compte : " ^ e
  | None -> "Aucun compte choisi"

let other_account_label t =
  match account t with
  | Some (_ : string) -> "Utiliser un autre compte"
  | None -> "Choisir un compte"

let status_line t =
  match t.phase with
  | Authorizing (_ : string) -> Some "Connexion à Google Drive…"
  | Storing (_ : string) -> Some "Enregistrement…"
  | Renaming _ -> Some "Renommage du dossier…"
  | Choosing _ | Idle (_ : string option) | Closed -> None
