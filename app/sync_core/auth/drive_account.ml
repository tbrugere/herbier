type t = Unconfigured | Unchosen | Chosen of {email : string}
[@@deriving eq, show]

let of_stored ~configured stored =
  match (configured, Option.map String.trim stored) with
  | false, _ -> Unconfigured
  | true, (None | Some "") -> Unchosen
  | true, Some email -> Chosen {email}

let email = function
  | Chosen {email} -> Some email
  | Unconfigured | Unchosen -> None

type unavailable = No_client | No_account [@@deriving eq, show]

let request = function
  | Chosen {email} -> Ok email
  | Unchosen -> Error No_account
  | Unconfigured -> Error No_client

type choose_error = Cancelled | No_google_account | Choose_failed
[@@deriving eq, show]

(* The codes GoogleAuthorizationPlugin.java's chooseAccount rejects with. *)
let choose_error_of_code = function
  | Some "USER_CANCELLED" -> Cancelled
  | Some "NO_CREDENTIAL" -> No_google_account
  | Some _ | None -> Choose_failed
