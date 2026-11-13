(** A GoTrue grant's outcome, sans IO: the fetch's failure or GoTrue's answer,
    and the one reading of a refresh's answer, shared by the app's session and
    the keep-alive job's. *)

type error =
  | Network of string  (** the fetch failed or timed out *)
  | Rejected of Gotrue.error  (** any answer that is not a session *)

val error_to_string : error -> string
(** ["network: <why>"], or {!Gotrue.error_to_string}. *)

type refreshed =
  | Fresh of Session.t
  | Revoked of Gotrue.error
      (** {!Gotrue.revokes_session}: this session is gone for good *)
  | Failed of error  (** any other failure: worth a retry *)

val refreshed : (Session.t, error) result -> refreshed
(** A refresh grant's result, classified. *)
