(** The GoTrue calls themselves, over {!Herbier_bindings.Timed_fetch}, on this
    build's {!Backend}: the app's session ({!Auth}) and the keep-alive job's
    ({!Keepalive}) are made, refreshed and logged out through them. No state, no
    log. *)

module Gotrue := Herbier_sync_core.Auth.Gotrue
module Session := Herbier_sync_core.Auth.Session
module Grant := Herbier_sync_core.Auth.Grant

type error = Grant.error =
  | Network of string  (** the fetch failed or timed out *)
  | Rejected of Gotrue.error  (** any answer that is not a session *)

val error_to_string : error -> string
(** {!Grant.error_to_string}. *)

val id_token_grant :
  raw_nonce:string -> id_token:string -> (Session.t, error) result Fut.t
(** {!Gotrue.id_token_grant}, decoded with the clock read when it is sent. *)

type refreshed = Grant.refreshed =
  | Fresh of Session.t
  | Revoked of Gotrue.error
      (** {!Gotrue.revokes_session}: this session is gone for good *)
  | Failed of error  (** any other failure: worth a retry *)

val refresh : Session.t -> refreshed Fut.t
(** {!Gotrue.refresh_grant} with the session's refresh token, decoded with the
    clock read when it is sent, read by {!Grant.refreshed}: the app's session's
    ({!Auth}) and the keep-alive job's ({!Keepalive}). *)

val logout : Session.t -> (unit, error) result Fut.t
(** {!Gotrue.logout} with this session's access token (scope local: this session
    only). [Error] when the fetch failed or GoTrue answered an error; the caller
    logs it. *)
