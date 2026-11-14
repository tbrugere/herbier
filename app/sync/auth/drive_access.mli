(** The Drive access token (architecture §5, "Drive token"), asked of Play
    Services through {!Herbier_bindings.Cap_google_authorization} at each call:
    it caches the 1-hour token and renews it, Herbier stores none. Internal to
    the [Auth] group, which re-exports it as [Auth.drive_token]; the contract is
    documented there ([Auth.drive_error], [Auth.drive_token]). *)

type error =
  | Drive_unconfigured
  | Drive_signed_out
  | Consent_needed
  | Consent_refused
  | Drive_offline
  | Drive_misconfigured
  | No_google_account
  | Drive_google of Herbier_bindings.Cap_error.t

val equal_error : error -> error -> bool
val error_to_string : error -> string

(** What [Auth] reads from its status at the call ([Restoring], and a session
    without an email, count as [Signed_out]). *)
type account = Unconfigured | Signed_out | Signed_in of {email : string}

type t
(** The interactive request in flight, if any. *)

val create : unit -> t

val token : t -> account -> interactive:bool -> (string, error) result Fut.t
(** [Auth.drive_token] for that account. Interactive calls are single-flight on
    [t], whatever the account: a call made while another runs gets that one's
    result (the app has one account; a second account's call during a consent
    screen would get the first's token). *)

val drop : string -> unit Fut.t
(** [Cap_google_authorization.clear_token] of that token; its outcome is a
    console line. Resolves once the plugin answered. *)
