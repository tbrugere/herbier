(** The GoTrue calls themselves, over {!Herbier_bindings.Timed_fetch}, on this
    build's {!Backend}: the app's session ({!Auth}) and the keep-alive job's
    ({!Keepalive}) are made, refreshed and logged out through them. No state, no
    log. *)

type error =
  | Network of string  (** the fetch failed or timed out *)
  | Rejected of Gotrue.error  (** any answer that is not a session *)

val error_to_string : error -> string
(** ["network: <why>"], or {!Gotrue.error_to_string}. *)

val id_token_grant :
  raw_nonce:string -> id_token:string -> (Session.t, error) result Fut.t
(** {!Gotrue.id_token_grant}, decoded with the clock read when it is sent. *)

val refresh : Session.t -> (Session.t, error) result Fut.t
(** {!Gotrue.refresh_grant} with the session's refresh token, decoded with the
    clock read when it is sent. *)

val logout : Session.t -> (unit, error) result Fut.t
(** {!Gotrue.logout} with this session's access token (scope local: this session
    only). [Error] when the fetch failed or GoTrue answered an error; the caller
    logs it. *)
