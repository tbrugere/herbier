(** Runs {!Geocode} requests in the WebView: one request in flight at a time
    across both providers, FIFO, and at least {!spacing_ms} between the starts
    of two requests to the same provider (Géoplateforme announces one request
    per second; Photon asks for fair use). No custom header (architecture.md,
    the WebView's User-Agent). *)

type error =
  | Network of string  (** offline, DNS, CORS; the browser's message *)
  | Timeout
  | Status of {provider : Geocode.provider; status : int}
      (** a response outside 200–299 (429 included) *)
  | Payload of Geocode.error  (** not JSON, or a decoder's [Unexpected] *)

val error_to_string : error -> string

val transient : error -> bool
(** [true] for [Network _], [Timeout], and a [Status] of 429 or 500–599: the
    same request may succeed later. [false] for a [Payload] and any other
    status. *)

val spacing_ms : int
(** 1000 *)

val default_timeout_ms : int
(** 10_000, counted from the request's start *)

val run :
  ?timeout_ms:int ->
  ?on_start:(Geocode.request -> unit) ->
  ('a, Geocode.error) result Geocode.program ->
  ('a, error) result Fut.t
(** Each [Get] through the queue; a body that [Geocode.json_of_string] rejects →
    [Error (Payload (Not_json _))]; a transport error stops the program with it;
    [Done (Error e)] → [Error (Payload e)]. Never raises; the future is
    determined unless a continuation raises (a bug, not caught). [on_start] is
    called with each request when it starts (after its wait in the queue and the
    spacing), for the dev log. *)

val reverse :
  ?timeout_ms:int ->
  ?on_start:(Geocode.request -> unit) ->
  Herbier_domain.Places.point ->
  (string option, error) result Fut.t
(** [run (Geocode.reverse p)]. *)

val search :
  ?timeout_ms:int ->
  ?on_start:(Geocode.request -> unit) ->
  ?near:Herbier_domain.Places.point ->
  string ->
  (Geocode.place list, error) result Fut.t
(** One [Geocode.photon_search] decoded by [Geocode.photon_places]. A blank
    query resolves [Ok []] with no request. *)
