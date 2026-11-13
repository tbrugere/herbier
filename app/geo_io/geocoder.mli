(** Runs {!Geocode} requests in the WebView: one request in flight at a time
    across both providers, FIFO, and at least {!spacing_ms} between the starts
    of two requests to the same provider (Géoplateforme announces one request
    per second; Photon asks for fair use). No custom header (architecture.md,
    the WebView's User-Agent).

    [Geocoder] does not read settings: callers gate what they send (App through
    [Place_name.resolve], 5b through [Place_name.can_search]), and pass an
    [allow] predicate read again when each request leaves the queue, so a source
    turned off while a request waits stops it (one already sent cannot be
    withdrawn). Every request is logged when it starts, on the console as
    [geocode: GET <provider> <endpoint>] (no query, so no coordinates or search
    text) and to every {!observe}r, so "no request left the phone" is checkable.
*)

type error =
  | Network of string  (** offline, DNS, CORS; the browser's message *)
  | Timeout
  | Status of {provider : Herbier_geo.Geocode.provider; status : int}
      (** a response outside 200–299 (429 included) *)
  | Payload of Herbier_geo.Geocode.error
      (** not JSON, or a decoder's [Unexpected] *)
  | Refused of Herbier_geo.Geocode.provider
      (** [allow] said no when the request left the queue: nothing was sent *)

val error_to_string : error -> string

val transient : error -> bool
(** [true] for [Network _], [Timeout], and a [Status] of 429 or 500–599: the
    same request may succeed later. [false] for a [Payload] and any other
    status, and for [Refused _]. *)

val spacing_ms : int
(** 1000 *)

val default_timeout_ms : int
(** 10_000, counted from the request's start *)

val run :
  ?timeout_ms:int ->
  ?on_start:(Herbier_geo.Geocode.request -> unit) ->
  ?allow:(Herbier_geo.Geocode.request -> bool) ->
  ('a, Herbier_geo.Geocode.error) result Herbier_geo.Geocode.program ->
  ('a, error) result Fut.t
(** Each [Get] through the queue; a body that
    [Herbier_geo.Geocode.json_of_string] rejects →
    [Error (Payload (Not_json _))]; a transport error stops the program with it;
    [Done (Error e)] → [Error (Payload e)]. Never raises; the future is
    determined unless a continuation raises (a bug, not caught). [on_start] is
    called with each request when it starts (after its wait in the queue and the
    spacing, and after the request is logged), for the dev log. [allow]
    (default: always) is asked at that same moment, before anything is logged or
    sent: [false] stops the program with [Error (Refused provider)]. *)

val search :
  ?timeout_ms:int ->
  ?on_start:(Herbier_geo.Geocode.request -> unit) ->
  ?allow:(Herbier_geo.Geocode.request -> bool) ->
  ?near:Herbier_domain.Places.point ->
  string ->
  (Herbier_geo.Geocode.place list, error) result Fut.t
(** One [Herbier_geo.Geocode.photon_search] decoded by
    [Herbier_geo.Geocode.photon_places]. A blank query resolves [Ok []] with no
    request. *)

val observe : (Herbier_geo.Geocode.request -> unit) -> unit
(** Calls [f] with every request that starts from now on, before it is sent
    (after [allow]). For the dev hook's request list; nothing registers one in a
    release build. *)
