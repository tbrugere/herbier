(** The Drive grant as Herbier asks for it: the scope, and what the
    GoogleAuthorization plugin's rejection codes mean (architecture §5, "Drive
    token"). *)

val scope : string
(** ["https://www.googleapis.com/auth/drive.file"]: files Herbier created (or
    the user opened with it), nothing else; non-sensitive, so no OAuth
    verification (stack.md). The plugin refuses any other scope. *)

type refusal =
  | Consent_needed
      (** ["NEEDS_CONSENT"]: not granted yet (or revoked); only an interactive
          request can grant it *)
  | Consent_refused
      (** ["USER_CANCELLED"] or ["SCOPE_NOT_GRANTED"]: the user dismissed the
          consent screen or unchecked Drive *)

val equal_refusal : refusal -> refusal -> bool

val refusal_of_code : string option -> refusal option
(** The plugin rejection's [code]: the three above, exact match
    (case-sensitive); anything else, and [None], → [None] (an ordinary failure).
*)

(** A Play Services failure whose status changes what a caller does. *)
type failure =
  | Offline  (** ["NETWORK_ERROR"] (status 7): retry later *)
  | Misconfigured
      (** ["DEVELOPER_ERROR"] (status 10): the OAuth client does not match the
          app's package or signing key; retrying does not help *)
  | No_google_account
      (** ["SIGN_IN_REQUIRED"] (status 4): no usable Google account on the
          device *)

val equal_failure : failure -> failure -> bool

val failure_of_code : string option -> failure option
(** The plugin rejection's [code]: the three above, exact match; anything else
    (["AUTHORIZATION_FAILED"], …) and [None] → [None]. *)
