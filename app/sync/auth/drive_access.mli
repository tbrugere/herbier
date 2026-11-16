(** The Drive access token (architecture §5, "Drive token"), asked of Play
    Services through {!Herbier_bindings.Cap_google_authorization} at each call
    for the Drive account the user chose in 4m
    ({!Herbier_sync_core.Auth.Drive_account}): Play Services caches the 1-hour
    token and renews it, Herbier stores none. Internal to the [Auth] group,
    which re-exports it as [Auth.drive_token]; the contract is documented there
    ([Auth.drive_error], [Auth.drive_token], [Auth.choose_drive_account]). *)

type error =
  | Drive_unconfigured
  | Drive_no_account
  | Consent_needed
  | Consent_refused
  | Drive_offline
  | Drive_misconfigured
  | No_google_account
  | Drive_google of Herbier_bindings.Cap_error.t

val equal_error : error -> error -> bool
val error_to_string : error -> string

type t
(** The interactive requests in flight, by email. *)

val create : unit -> t

val configured : bool
(** [Backend.google_web_client_id <> ""]: the chooser's server client id. *)

val token :
  t ->
  Herbier_sync_core.Auth.Drive_account.t ->
  interactive:bool ->
  (string, error) result Fut.t
(** [Auth.drive_token] for that Drive account; the Supabase session is not read.
    Interactive calls are single-flight per email: a call for the same email
    while one runs gets that one's result; a call for another email goes to the
    plugin (a consent for one account never answers a request for another). *)

type choose_error = Herbier_sync_core.Auth.Drive_account.choose_error =
  | Cancelled
  | No_google_account
  | Choose_failed

val choose : unit -> (string, choose_error) result Fut.t
(** [Auth.choose_drive_account]. *)

val drop : string -> unit Fut.t
(** [Cap_google_authorization.clear_token] of that token; its outcome is a
    console line. Resolves once the plugin answered. *)
