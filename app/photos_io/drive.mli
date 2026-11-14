(** Runs {!Herbier_photos.Drive} programs on the device: each request over
    {!Herbier_bindings.Timed_fetch} with [Authorization: Bearer <token>], the
    multipart media part from a Blob. The token comes from the caller (the
    account lives in herbier_sync, a sibling this library does not import): the
    caller passes [Auth.drive_token] and [Auth.drop_drive_token]. *)

module Api := Herbier_photos.Drive

type 'e error =
  | Token of 'e  (** the token source failed; no request was sent after it *)
  | Drive of Api.error

val error_to_string : ('e -> string) -> 'e error -> string
(** ["token: <e>"] or ["drive: <Api.error_to_string>"]; never a token. *)

val upload_timeout_ms : int
(** 300 000: the multipart [files.create] (several MB on a slow uplink); every
    other request uses {!Herbier_bindings.Timed_fetch.timeout_ms}. *)

val put_original :
  token:(unit -> (string, 'e) result Fut.t) ->
  drop_token:(string -> unit Fut.t) ->
  Api.original ->
  Brr.Blob.t ->
  (Api.put, 'e error) result Fut.t
(** Runs {!Api.put_original}, the original's bytes as the multipart media. Asks
    [token] once ([Error e] → [Error (Token e)], no request sent), then sends
    the program's requests one after another, adding
    [Authorization: Bearer <token>] and {!Api.content_type}. A [Multipart] body
    is sent as a Blob of [prefix] (UTF-8 text), the media, [suffix] through
    [Timed_fetch.request_blob ~timeout_ms:upload_timeout_ms]; other bodies
    through [Timed_fetch.request]. A 401: [drop_token] that token, ask [token]
    again ([Error e] → [Error (Token e)]), resend that same request once with
    the new token (kept for the requests after it); a second 401 goes to the
    program (→ [Drive Unauthorized]). A fetch [Error Timeout | Failed m] is
    answered to the program as [Unreachable m] (["timeout"] for [Timeout]). The
    program's [Error x] → [Error (Drive x)]. Each request is one console line «
    drive: <METH> <URL path, no query> → <status or failure> » (never the token,
    never the query: it holds species names). Never raises; the future always
    resolves. *)

val start_session :
  token:(unit -> (string, 'e) result Fut.t) ->
  drop_token:(string -> unit Fut.t) ->
  Api.target ->
  (Api.start, 'e error) result Fut.t
(** Runs {!Api.start_session} as {!put_original} runs its program (token asked
    once, one renewal on a 401, every body JSON or empty through
    [Timed_fetch.request] with the default timeout, the same console line per
    request: never the token, the query or the session URL, which is only in the
    last answer's headers). Never raises. *)

val presence :
  token:(unit -> (string, 'e) result Fut.t) ->
  drop_token:(string -> unit Fut.t) ->
  file_id:string ->
  (Api.presence, 'e error) result Fut.t
(** Runs {!Api.presence} the same way as {!put_original} (one request). *)

val boundary : unit -> (string, string) result
(** {!Api.boundary} over 16 bytes of [Web_crypto.random_bytes]; WebCrypto's
    error message otherwise (the binding's own error is a string). *)
