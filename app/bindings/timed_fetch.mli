(** A fetch aborted after a timeout, its answer read as text. *)

val timeout_ms : int
(** 15 000, the default timeout. *)

type response = {status : int; headers : (string * string) list; body : string}
(** Header names lowercased (as the Fetch API gives them). *)

type meth = [`DELETE | `GET | `PATCH | `POST]

val meth_to_string : meth -> string
(** ["DELETE"], ["GET"], ["PATCH"], ["POST"]. *)

type error =
  | Timeout  (** aborted after the timeout ({!timeout_ms} by default) *)
  | Failed of string
      (** the fetch rejected, or the headers could not be built (a value fetch
          refuses, e.g. a control character): from {!request} the JS error's
          name and message (["TypeError: Failed to fetch"]), from {!get} its
          message alone (["Failed to fetch"]). The text may hold the URL: a
          caller whose URL holds a secret must not log or show it. *)

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

val request_blob :
  ?timeout_ms:int ->
  meth:meth ->
  url:string ->
  headers:(string * string) list ->
  Brr.Blob.t ->
  (response, error) result Fut.t
(** {!request} with a binary body sent as is (a [Blob]: an upload's bytes, which
    a [string] body would re-encode as UTF-8), aborted after [timeout_ms]
    (default {!timeout_ms}). Same answer, errors and guarantees as {!request}: a
    non-2xx status is [Ok], its body read; never raises. *)

type form_file = {field : string; filename : string; blob : Brr.Blob.t}
(** A file part of a form: its [field] name, the [filename] put in its
    Content-Disposition, and its bytes. *)

val request_form :
  ?timeout_ms:int ->
  url:string ->
  fields:(string * string) list ->
  form_file list ->
  (response, error) result Fut.t
(** One [POST] to [url] with a fresh [FormData] body: every [(name, value)] of
    [fields] as a text part, in order, then every file part, in order. No header
    is set: the WebView sets [Content-Type: multipart/form-data; boundary=…] (a
    caller's Content-Type would break the boundary, so none can be given).
    Aborted after [timeout_ms] (default {!timeout_ms}). Same answers, errors and
    guarantees as {!request}: a non-2xx status is [Ok], its body read; never
    raises. *)

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
