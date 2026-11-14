(* Equal to GoogleAuthorizationPlugin.java's DRIVE_FILE: the plugin grants no
   other scope. *)
let scope = "https://www.googleapis.com/auth/drive.file"

type refusal = Consent_needed | Consent_refused [@@deriving eq]

(* The codes GoogleAuthorizationPlugin.java rejects with. *)
let refusal_of_code = function
  | Some "NEEDS_CONSENT" -> Some Consent_needed
  | Some ("USER_CANCELLED" | "SCOPE_NOT_GRANTED") -> Some Consent_refused
  | Some _ | None -> None

type failure = Offline | Misconfigured | No_google_account [@@deriving eq]

let failure_of_code = function
  | Some "NETWORK_ERROR" -> Some Offline
  | Some "DEVELOPER_ERROR" -> Some Misconfigured
  | Some "SIGN_IN_REQUIRED" -> Some No_google_account
  | Some _ | None -> None
