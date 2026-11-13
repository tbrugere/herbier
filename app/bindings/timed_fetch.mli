(** A fetch aborted after a timeout, its answer read as text. *)

val timeout_ms : int
(** 15 000. *)

type response = {status : int; headers : (string * string) list; body : string}
(** Header names lowercased (as the Fetch API gives them). *)

type meth = [`DELETE | `GET | `PATCH | `POST]

val meth_to_string : meth -> string
(** ["DELETE"], ["GET"], ["PATCH"], ["POST"]. *)

type error =
  | Timeout  (** aborted after {!timeout_ms} *)
  | Failed of string
      (** the fetch rejected (["TypeError: Failed to fetch"]: the JS error's
          name and message), or the headers could not be built (a value fetch
          refuses, e.g. a control character) *)

val error_to_string : error -> string
(** ["timeout"], or the [Failed] message. *)

val request :
  meth:meth ->
  url:string ->
  headers:(string * string) list ->
  body:string option ->
  (response, error) result Fut.t
(** One fetch, aborted after {!timeout_ms}. A non-2xx status is [Ok]. Never
    raises; the future always resolves. *)
