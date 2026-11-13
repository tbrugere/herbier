(** A fetch aborted after a timeout, its answer read as text. *)

val timeout_ms : int
(** 15 000, the default timeout. *)

type response = {status : int; headers : (string * string) list; body : string}
(** Header names lowercased (as the Fetch API gives them). *)

type meth = [`DELETE | `GET | `PATCH | `POST]

val meth_to_string : meth -> string
(** ["DELETE"], ["GET"], ["PATCH"], ["POST"]. *)

type error =
  | Timeout  (** aborted after {!timeout_ms} *)
  | Failed of string
      (** the fetch rejected, or the headers could not be built (a value fetch
          refuses, e.g. a control character): from {!request} the JS error's
          name and message (["TypeError: Failed to fetch"]), from {!get} its
          message alone (["Failed to fetch"]) *)

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

(** What {!get} does with the body of a response outside 200–299. *)
type non_2xx_body =
  | Read  (** read like a 2xx: a body that fails to read is an [Error] *)
  | Read_or_empty  (** read; a body that fails to read gives [body = ""] *)
  | Skip
      (** not read: [body = ""], and the timer stops as soon as the status is
          known *)

val get :
  ?timeout_ms:int ->
  ?non_2xx_body:non_2xx_body ->
  ?headers:(string * string) list ->
  string ->
  (response, error) result Fut.t
(** [get url]: one GET, aborted after [timeout_ms] (default {!timeout_ms}), with
    [headers] (default none). A non-2xx status is [Ok], its body as
    [non_2xx_body] says (default [Read], as {!request}). A 2xx body that fails
    to read is an [Error]. Never raises; the future always resolves. *)
