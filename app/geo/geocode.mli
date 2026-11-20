(** Geocoding requests and payloads (architecture §8, stack.md « Geocoding »):
    Photon (komoot) forward and reverse, IGN Géoplateforme reverse for points in
    France. Pure: URLs, decoders and the reverse programs; run by [Geocoder] on
    the device and by a function standing for the network in tests. Nothing here
    raises. *)

module Places := Herbier_domain.Places

type provider = Photon | Geoplateforme

val provider_to_string : provider -> string
(** ["photon"] / ["geoplateforme"]: logs, and the provider column of
    scripts/record-geo-fixtures.sh. *)

type request = private {provider : provider; url : string}

val equal_request : request -> request -> bool

val request_to_string : request -> string
(** ["<provider> <url>"], the whole URL: the dev log and hook. *)

val request_endpoint : request -> string
(** ["<provider> <url before ?>"], e.g.
    ["photon https://photon.komoot.io/reverse"]: no coordinates and no query,
    for the console. *)

val coordinate : float -> string
(** [Printf.sprintf "%.5f"]: ["48.06330"], ["-0.85000"], [48.0633512] →
    ["48.06335"]. About 1 m: no coarser than a phone's fix, so the providers get
    the observation's position as recorded. *)

val photon_reverse : Places.point -> request
(** [https://photon.komoot.io/reverse?lat=<lat>&lon=<lon>&lang=fr&limit=1&layer=city&layer=district&layer=locality],
    coordinates by {!coordinate}. *)

val photon_search : ?near:Places.point -> ?limit:int -> string -> request
(** [https://photon.komoot.io/api?q=<encode q>&lang=fr&limit=<limit>] then, with
    [near], [&lat=<lat>&lon=<lon>] (location bias). [limit] defaults to 8 and is
    clamped to [1, 20]. [q] is sent as given (not trimmed). *)

val geoplateforme_lieu_dit : Places.point -> request
(** The nearest named lieu-dit within 500 m:
    [https://data.geopf.fr/geocodage/reverse?index=poi&lon=<lon>&lat=<lat>&limit=1&category=<encode
     "lieu-dit habité,lieu-dit non habité">&searchgeom=<encode
     {"type":"Circle","coordinates":[<lon>,<lat>],"radius":500}>]: the radius is
    [Places.radius_m] capped at the API's maximum, 500. The JSON is written
    without spaces, coordinates by {!coordinate}. *)

val geoplateforme_commune : Places.point -> request
(** The commune containing the point:
    [https://data.geopf.fr/geocodage/reverse?index=poi&lon=<lon>&lat=<lat>&limit=1&category=commune&searchgeom=<encode
     {"type":"Point","coordinates":[<lon>,<lat>]}>]. Empty outside France. *)

val geoplateforme_wfs : (string * string) list -> request
(** [{provider = Geoplateforme; url}] with
    [url = "https://data.geopf.fr/wfs/ows?k1=v1&k2=v2…"], each key and value
    through {!encode}, in the given order: the IGN commune packs of [Communes].
    The only way to build a WFS request ([request] stays private: a
    Géoplateforme request always targets data.geopf.fr). Never raises. *)

val in_france : Places.point -> bool
(** Coarse box of metropolitan France and Corsica: [41.3 <= lat <= 51.2] and
    [-5.5 <= lon <= 9.7], inclusive. It also holds parts of the neighbours
    (Geneva, Basel, Barcelona, the Channel): those get empty Géoplateforme
    answers and fall back to Photon. [false] for a [nan] coordinate. Overseas
    France is outside the box (Photon). *)

type error =
  | Not_json of string  (** the body is not JSON; the parser's message *)
  | Unexpected of {path : string; expected : string}
      (** a required field is missing or of the wrong type; [path] is a JSON
          pointer (["/features"]) *)

val error_to_string : error -> string
val equal_error : error -> error -> bool

val transient_status : int -> bool
(** [429] or [500]–[599]: an HTTP status after which the same request may
    succeed later. *)

val json_of_string : string -> (Yojson.Safe.t, error) result
(** [Yojson.Safe.from_string], any exception → [Not_json]. *)

(** {1 Payload helpers}

    Shared by the decoders here and by [Communes]'s WFS decoders. *)

val max_value_bytes : int
(** [200]: a longer provider string is not a place name (it would be synced as
    is). *)

val non_blank : string -> string option
(** [String.trim s] when it is non-empty and at most {!max_value_bytes} bytes;
    else [None]. *)

val string : string -> Yojson.Safe.t -> string option
(** The field [name] when a string passing {!non_blank}, trimmed. *)

val properties : Yojson.Safe.t -> Yojson.Safe.t
(** A feature's [properties], [`Assoc []] when absent. *)

val features : Yojson.Safe.t -> (Yojson.Safe.t list, error) result
(** A FeatureCollection's [features];
    [Unexpected {path = "/features"; expected = "array"}] when not an array. *)

val photon_name : Yojson.Safe.t -> (string option, error) result
(** A Photon reverse payload. [features] must be an array
    ([Unexpected {path = "/features"; expected = "array"}] otherwise). [Ok None]
    when it is empty. From the first feature's [properties]: its [name] when
    [osm_key] is ["place"] and [osm_value] is one of city, town, village,
    hamlet, isolated_dwelling, farm, suburb, quarter, neighbourhood, borough,
    locality, island, islet; else [district]; else [city]; else [Ok None]. Each
    of these fields is optional: missing, [null], not a string, or blank after
    trimming or longer than 200 bytes counts as absent ({!string}); the string
    is returned trimmed. *)

val geoplateforme_name : Yojson.Safe.t -> (string option, error) result
(** A Géoplateforme reverse payload. [features] must be an array (as above);
    [Ok None] when empty. The first feature's [properties.toponym], else the
    first non-blank string of [properties.name] (an array), else [Ok None]. A
    value longer than 200 bytes counts as absent, as for Photon. *)

type place = {
  name : string;  (** non-blank *)
  context : string option;
      (** [city], [county], [country]: the non-blank ones that differ from
          [name] and from each other, in that order, joined by [", "]; [None]
          when none *)
  point : Places.point;  (** from [geometry.coordinates] = [[lon, lat]] *)
}

val equal_place : place -> place -> bool

val photon_places : Yojson.Safe.t -> (place list, error) result
(** A Photon search payload, in the payload's order. [features] must be an
    array; a feature without a non-blank [properties.name] of at most 200 bytes
    or without two finite numbers (int or float JSON) in [geometry.coordinates]
    is skipped (style §8.4), never an error. *)

(** {1 The reverse programs}

    Which of them run, and in which order, is [Place_name.resolve]'s rule. *)

(* style: transparent: Geocoder.run and the tests match on it. A transport
   failure never reaches a continuation: the runner stops with its own
   error. *)
type 'a program = Done of 'a | Get of request * (Yojson.Safe.t -> 'a program)

val map : ('a -> 'b) -> 'a program -> 'b program
(** Applies [f] to the [Done] value; the requests are those of the program, in
    order. *)

val or_else :
  ('a option, error) result program ->
  (unit -> ('a option, error) result program) ->
  ('a option, error) result program
(** [or_else p next]: runs [p]; [Done (Ok None)] → [next ()];
    [Done (Ok (Some _))] and [Done (Error _)] end there ([next] is not called,
    no request of [next] is issued). *)

val reverse_ign : Places.point -> (string option, error) result program
(** « IGN en ligne »: when {!in_france}: [geoplateforme_lieu_dit] → a name →
    [Done (Ok (Near.phrase name))]; none → [geoplateforme_commune] → a name →
    [Done (Ok (Near.phrase name))]; none → [Done (Ok None)]. Outside the box:
    [Done (Ok None)] with no request. A payload that does not decode →
    [Done (Error e)] at once (no commune request after a bad lieu-dit payload).
    A name that [Near.phrase] rejects counts as none. *)

val reverse_photon : Places.point -> (string option, error) result program
(** « Photon en ligne »: [photon_reverse] → {!photon_name} → a name →
    [Done (Ok (Near.phrase name))]; none → [Done (Ok None)]; bad payload →
    [Done (Error e)]. One request, anywhere in the world. *)
