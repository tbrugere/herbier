(** Geocoding requests and payloads (architecture §8, stack.md « Geocoding »):
    Photon (komoot) forward and reverse, IGN Géoplateforme reverse for points in
    France. Pure: URLs, decoders and the reverse program; run by [Geocoder] on
    the device and by a function standing for the network in tests. Nothing here
    raises. *)

module Places := Herbier_domain.Places

type provider = Photon | Geoplateforme

val provider_to_string : provider -> string
(** ["photon"] / ["geoplateforme"]: logs, and the provider column of
    scripts/record-geo-fixtures.sh. *)

type request = private {provider : provider; url : string}

val equal_request : request -> request -> bool

val encode : string -> string
(** Percent-encoding of a query key or value: every byte except the RFC 3986
    unreserved set [A-Z a-z 0-9 - . _ ~], upper-case hex. [" "] → ["%20"], [","]
    → ["%2C"], ["\""] → ["%22"], ["é"] → ["%C3%A9"]. A copy of
    [Herbier_refs.Request.encode] (layout.md, known copies). *)

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

val in_france : Places.point -> bool
(** Coarse box of metropolitan France and Corsica: [41.3 <= lat <= 51.2] and
    [-5.5 <= lon <= 9.7], inclusive. It also holds parts of the neighbours
    (Geneva, Basel, Barcelona, the Channel): those get empty Géoplateforme
    answers and fall back to Photon. [false] for a [nan] coordinate. Overseas
    France is outside the box (Photon). *)

val near : string -> string option
(** The stored [place_derived] phrase for a place name (handoff 4c « Près de
    Colmar »), French contraction applied to the trimmed name:
    - ["Le X"] → ["Près du X"], ["Les X"] → ["Près des X"], ["La X"] →
      ["Près de la X"], ["L'X"] or ["L’X"] → ["Près de l’X"]: the article
      matched case-insensitively (ASCII) and followed by a space (the apostrophe
      forms by nothing), replaced by the contracted form;
    - else a name starting with a vowel (ASCII [AEIOUY], either case, or one of
      [À Â Ä É È Ê Ë Î Ï Ô Ö Ù Û Ü Œ Æ] and their lower case) →
      ["Près d’" ^ name] (no elision before h);
    - else ["Près de " ^ name], also for a name made only of an article (["L'"]
      → ["Près de L'"]).

    [None] for a blank name. The apostrophe written is always [’] (U+2019).
    Never raises. *)

type error =
  | Not_json of string  (** the body is not JSON; the parser's message *)
  | Unexpected of {path : string; expected : string}
      (** a required field is missing or of the wrong type; [path] is a JSON
          pointer (["/features"]) *)

val error_to_string : error -> string
val equal_error : error -> error -> bool

val json_of_string : string -> (Yojson.Safe.t, error) result
(** [Yojson.Safe.from_string], any exception → [Not_json]. *)

val photon_name : Yojson.Safe.t -> (string option, error) result
(** A Photon reverse payload. [features] must be an array
    ([Unexpected {path = "/features"; expected = "array"}] otherwise). [Ok None]
    when it is empty. From the first feature's [properties]: its [name] when
    [osm_key] is ["place"] and [osm_value] is one of city, town, village,
    hamlet, isolated_dwelling, farm, suburb, quarter, neighbourhood, borough,
    locality, island, islet; else [district]; else [city]; else [Ok None]. Each
    of these fields is optional: missing, [null], not a string, or blank after
    trimming or longer than 200 bytes counts as absent; the string is returned
    as given. *)

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

(** {1 The reverse rule} *)

(* style: transparent: Geocoder.run and the tests match on it. A transport
   failure never reaches a continuation: the runner stops with its own
   error. *)
type 'a program = Done of 'a | Get of request * (Yojson.Safe.t -> 'a program)

val reverse : Places.point -> (string option, error) result program
(** The [place_derived] of a point:
    - {!in_france}: [geoplateforme_lieu_dit] → a name → [Done (Ok (near name))];
      none → [geoplateforme_commune] → a name → [Done (Ok (near name))]; none →
      the Photon step below;
    - otherwise (or after both empty answers): [photon_reverse] → a name →
      [Done (Ok (near name))]; none → [Done (Ok None)].

    A payload that does not decode ends the program at once with
    [Done (Error e)] (no fallback to the next provider: a later run retries). A
    name that [near] rejects (blank) counts as none. *)
