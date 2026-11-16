(** What {!Make} needs from the network, and nothing more: a POST of a multipart
    form and a GET, each answering a status and a body, or failing. A transport
    holds no key, reads no file of its own choosing and logs nothing. *)

type answer = {status : int; body : string}
(** Any HTTP status (a non-2xx is an answer, not a failure) and the body read as
    text. *)

type failure =
  | Timeout  (** no answer within the transport's own timeout *)
  | Network of string
      (** the request failed (offline, DNS, refused, a JS error), with the
          transport's text; {!Make} never shows it, since it may hold the URL
          (whose query string holds the key) *)

type 'image file = {field : string; filename : string; image : 'image}
(** A file part of the form: its form [field] name, the [filename] put in its
    Content-Disposition, and the image whose bytes the transport holds. *)

module type TRANSPORT = sig
  type 'a io

  val return : 'a -> 'a io
  val bind : 'a io -> ('a -> 'b io) -> 'b io

  type image
  (** A preview to send; the transport alone knows where its bytes are. *)

  val post_form :
    url:string ->
    fields:(string * string) list ->
    files:image file list ->
    (answer, failure) result io
  (** POST [url] with a [multipart/form-data] body: every [(name, value)] of
      [fields] as a text part, in order, then every file part, in order. The
      transport sets the boundary. Never fails in [io] itself: every failure is
      an [Error]. *)

  val get : url:string -> (answer, failure) result io
  (** GET [url], no body. Same answers and failures. *)
end
