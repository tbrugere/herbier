module Drive_account = Herbier_sync_core.Auth.Drive_account

type purpose = Change | Turn_on [@@deriving eq, show]

type phase =
  | Choosing of {previous : string option}
  | Authorizing of string
  | Browsing of string
  | Storing of string
  | Idle of string option
  | Closed
[@@deriving eq, show]

type t = {
  purpose : purpose;
  stored : string option;
  folder : Drive_text.folder;
  picker : Drive_text.picker_config;
  phase : phase;
  error : Drive_text.pick_error option;
}
[@@deriving eq, show]

let hidden_token fmt (_ : string) = Format.pp_print_string fmt "<token>"

type command =
  | Run_chooser
  | Ask_token of string
  | Open_picker of {account : string; token : (string[@printer hidden_token])}
  | Store_pick of {account : string; folder_id : string; folder_name : string}
  | Store_default of string
  | Close
[@@deriving eq, show]

type event =
  | Tap_other_account
  | Tap_browse
  | Tap_default
  | Tap_close
  | Chosen of string
  | Choose_failed of Drive_account.choose_error
  | Token of ((string[@printer hidden_token]), Drive_text.denial) result
  | Picker_picked of {id : string; name : string}
  | Picker_cancelled
  | Picker_failed of Drive_text.pick_error
  | Stored of (unit, Drive_text.pick_error) result
[@@deriving eq, show]

let account t =
  match t.phase with
  | Choosing {previous} -> previous
  | Authorizing a | Browsing a | Storing a -> Some a
  | Idle a -> a
  | Closed -> None

let stored_account t a =
  match t.stored with
  | Some s -> Herbier_domain.Text.same_email s a
  | None -> false

let closed t error = ({t with phase = Closed; error}, [Close])
let authorize t a = ({t with phase = Authorizing a}, [Ask_token a])

let browse t a token =
  ({t with phase = Browsing a}, [Open_picker {account = a; token}])

let store_pick t a ~id ~name =
  ( {t with phase = Storing a},
    [Store_pick {account = a; folder_id = id; folder_name = name}] )

let open_ ~purpose ~stored ~folder ~picker =
  let base = {purpose; stored; folder; picker; phase = Closed; error = None} in
  match (purpose, picker, Option.bind stored Herbier_domain.Text.non_blank) with
  | Turn_on, Picker_unconfigured, (_ : string option) ->
      closed base (Some Picker_unavailable)
  | (Change | Turn_on), (Picker_ready | Picker_unconfigured), None ->
      ({base with phase = Choosing {previous = None}}, [Run_chooser])
  | (Change | Turn_on), (Picker_ready | Picker_unconfigured), Some e ->
      authorize base e

let can_browse t =
  match (t.purpose, t.phase, t.picker) with
  | Change, Idle (Some (_ : string)), Picker_ready -> true
  | Turn_on, (_ : phase), (Picker_ready | Picker_unconfigured) -> false
  | Change, Idle (Some (_ : string)), Picker_unconfigured
  | Change, Idle None, (Picker_ready | Picker_unconfigured)
  | ( Change,
      ( Choosing _
      | Authorizing (_ : string)
      | Browsing (_ : string)
      | Storing (_ : string)
      | Closed ),
      _ ) ->
      false

let can_default t =
  match (t.purpose, t.phase) with
  | Turn_on, (_ : phase) -> false
  | Change, Idle (Some a) -> (
      match (stored_account t a, t.folder) with
      | true, Default -> false
      | true, Picked (_ : string) | false, (Default | Picked (_ : string)) ->
          true)
  | ( Change,
      ( Idle None
      | Choosing _
      | Authorizing (_ : string)
      | Browsing (_ : string)
      | Storing (_ : string)
      | Closed ) ) ->
      false

let busy t =
  match t.phase with
  | Choosing _ | Authorizing (_ : string) | Browsing (_ : string) | Storing _ ->
      true
  | Idle (_ : string option) | Closed -> false

let failed t account e = ({t with phase = Idle account; error = Some e}, [])

(* A tap acted on clears the error. *)
let tapped t phase commands = ({t with phase; error = None}, commands)

let step_change t event =
  match (t.phase, event) with
  | Closed, (_ : event) -> (t, [])
  | (Choosing _ | Authorizing _ | Browsing _ | Storing _ | Idle _), Tap_close ->
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
  | Authorizing a, Token (Ok token) -> (
      match t.picker with
      | Picker_ready -> browse t a token
      | Picker_unconfigured -> ({t with phase = Idle (Some a)}, []))
  (* A token refused for an account not stored yet: back to the stored one,
     so that « Par défaut » cannot store an account Drive refuses. *)
  | Authorizing a, Token (Error d) -> (
      match stored_account t a with
      | true -> failed t (Some a) (Token d)
      | false -> (
          match t.stored with
          | Some (_ : string) -> failed t t.stored (Other_account d)
          | None -> failed t None (Token d)))
  | Browsing a, Picker_picked {id; name} -> store_pick t a ~id ~name
  | Browsing a, Picker_cancelled -> ({t with phase = Idle (Some a)}, [])
  | Browsing a, Picker_failed e -> failed t (Some a) e
  | Storing (_ : string), Stored (Ok ()) -> ({t with phase = Closed}, [Close])
  | Storing a, Stored (Error e) -> failed t (Some a) e
  | Idle previous, Tap_other_account ->
      tapped t (Choosing {previous}) [Run_chooser]
  | Idle (Some a), Tap_browse when can_browse t ->
      tapped t (Authorizing a) [Ask_token a]
  | Idle (Some a), Tap_default when can_default t ->
      tapped t (Storing a) [Store_default a]
  | ( Choosing _,
      ( Tap_other_account | Tap_browse | Tap_default | Token _ | Picker_picked _
      | Picker_cancelled | Picker_failed _ | Stored _ ) )
  | ( Authorizing _,
      ( Tap_other_account | Tap_browse | Tap_default | Chosen _
      | Choose_failed _ | Picker_picked _ | Picker_cancelled | Picker_failed _
      | Stored _ ) )
  | ( Browsing _,
      ( Tap_other_account | Tap_browse | Tap_default | Chosen _
      | Choose_failed _ | Token _ | Stored _ ) )
  | ( Storing _,
      ( Tap_other_account | Tap_browse | Tap_default | Chosen _
      | Choose_failed _ | Token _ | Picker_picked _ | Picker_cancelled
      | Picker_failed _ ) )
  | ( Idle _,
      ( Tap_browse | Tap_default | Chosen _ | Choose_failed _ | Token _
      | Picker_picked _ | Picker_cancelled | Picker_failed _ | Stored _ ) ) ->
      (t, [])

let step_turn_on t event =
  match (t.phase, event) with
  | Closed, (_ : event) -> (t, [])
  | (Choosing _ | Authorizing _ | Browsing _ | Storing _ | Idle _), Tap_close ->
      closed t None
  | Choosing _, Chosen e -> (
      match Herbier_domain.Text.non_blank e with
      | Some e -> authorize t e
      | None -> closed t (Some Chooser_failed))
  | Choosing _, Choose_failed Cancelled -> closed t t.error
  | Choosing _, Choose_failed No_google_account ->
      closed t (Some Chooser_no_account)
  | Choosing _, Choose_failed Choose_failed -> closed t (Some Chooser_failed)
  | Authorizing a, Token (Ok token) -> (
      match t.picker with
      | Picker_ready -> browse t a token
      | Picker_unconfigured -> closed t (Some Picker_unavailable))
  (* The stored account refused (removed from the phone, consent withdrawn):
     the radio has no other way to « Utiliser un autre compte », so the
     chooser opens, once; the refusal is kept for a cancel to show. *)
  | Authorizing a, Token (Error d) -> (
      match (stored_account t a, t.error) with
      | true, None ->
          ( {t with phase = Choosing {previous = None}; error = Some (Token d)},
            [Run_chooser] )
      | true, Some (_ : Drive_text.pick_error)
      | false, (None | Some (_ : Drive_text.pick_error)) ->
          closed t (Some (Token d)))
  | Browsing a, Picker_picked {id; name} -> store_pick t a ~id ~name
  | Browsing (_ : string), Picker_cancelled -> closed t None
  | Browsing (_ : string), Picker_failed e -> closed t (Some e)
  | Storing (_ : string), Stored (Ok ()) -> closed t None
  | Storing (_ : string), Stored (Error e) -> closed t (Some e)
  | ( (Choosing _ | Authorizing _ | Browsing _ | Storing _ | Idle _),
      (Tap_other_account | Tap_browse | Tap_default) )
  | ( Choosing _,
      (Token _ | Picker_picked _ | Picker_cancelled | Picker_failed _ | Stored _)
    )
  | ( Authorizing _,
      ( Chosen _ | Choose_failed _ | Picker_picked _ | Picker_cancelled
      | Picker_failed _ | Stored _ ) )
  | Browsing _, (Chosen _ | Choose_failed _ | Token _ | Stored _)
  | ( Storing _,
      ( Chosen _ | Choose_failed _ | Token _ | Picker_picked _
      | Picker_cancelled | Picker_failed _ ) )
  | ( Idle _,
      ( Chosen _ | Choose_failed _ | Token _ | Picker_picked _
      | Picker_cancelled | Picker_failed _ | Stored _ ) ) ->
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

let folder_line t =
  match account t with
  | None -> None
  | Some a -> (
      match (stored_account t a, t.folder) with
      | true, Picked (_ : string) ->
          Some ("Dossier : " ^ Drive_text.folder_name t.folder)
      | true, Default | false, (Default | Picked (_ : string)) ->
          Some ("Dossier : " ^ Drive_text.app_folder))

let status_line t =
  match t.phase with
  | Authorizing (_ : string) -> Some "Connexion à Google Drive…"
  | Browsing (_ : string) -> Some "Ouverture de Google Drive…"
  | Storing (_ : string) -> Some "Enregistrement…"
  | Choosing _ | Idle (_ : string option) | Closed -> None

let picker_note t =
  match (t.purpose, t.picker) with
  | Change, Picker_unconfigured ->
      Some
        "Choix du dossier indisponible dans cette version : les photos vont \
         dans « Herbier »."
  | Change, Picker_ready | Turn_on, (Picker_ready | Picker_unconfigured) -> None

let picker_title email = "Dossier Drive · " ^ email
