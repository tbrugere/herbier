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
    without spaces, coordinates by {!coordinate}. Wider than {!detail_max_m},
    which {!geoplateforme_detail} applies to the answer: a lieu-dit between the
    two is still decoded, then dropped by distance. The reverse answer comes
    nearest first, so the one feature asked for is the one a request of
    {!detail_max_m} would give, and the recorded fixtures keep the farther
    lieux-dits that exercise the distance rule. *)

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

type named = {
  name : string;
      (** the [place_derived] to store: « Près de <commune> » ({!Near.phrase}),
          or a user's label verbatim *)
  detail : string option;
      (** the [place_detail] to store: a lieu-dit's own name as the provider
          spells it (no « Près de »), close to the point and not the commune's
          name *)
}

val equal_named : named -> named -> bool

val named_to_string : named -> string
(** ["<name>"], or ["<name> / <detail>"]: logs and the dev page. *)

val detail_max_m : float
(** [200.]: how close a lieu-dit must be to the point to be its detail: about
    the extent of a hamlet (architecture §8). *)

val same_name : string -> string -> bool
(** Equal after [String.trim] and [String.lowercase_ascii]: « Figeac » and «
    figeac », « le Valtin » and « Le Valtin ». No accent folding. *)

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

val photon_commune : Yojson.Safe.t -> (string option, error) result
(** A Photon reverse payload's commune. [features] must be an array
    ([Unexpected {path = "/features"; expected = "array"}] otherwise); [Ok None]
    when it is empty. From the first feature's [properties]: its [city]; else
    its [name] when [osm_key] is ["place"] and [osm_value] is city, town or
    village (a feature that is itself the commune carries no [city]); else
    [district]; else its [name] when [osm_key] is ["place"] and [osm_value] is
    one of hamlet, isolated_dwelling, farm, suburb, quarter, neighbourhood,
    borough, locality, island, islet (abroad, where no city is given); else
    [Ok None]. Each of these fields is optional: missing, [null], not a string,
    or blank after trimming or longer than 200 bytes counts as absent
    ({!string}); the string is returned trimmed. *)

val photon_detail :
  near:Places.point ->
  commune:string ->
  Yojson.Safe.t ->
  (string option, error) result
(** The same payload's lieu-dit: the first feature's [name] (through {!string})
    when [osm_key] is ["place"], [osm_value] is one of hamlet,
    isolated_dwelling, farm, locality, neighbourhood, its point
    ([geometry.coordinates], two finite numbers [[lon, lat]]) is within
    [detail_max_m +. 1e-3] of [near] ([Places.distance_m], inclusive) and it is
    not {!same_name} as [commune]; else [Ok None]. [features] not an array → the
    usual [Unexpected]; empty → [Ok None]. *)

val geoplateforme_name : Yojson.Safe.t -> (string option, error) result
(** A Géoplateforme reverse payload. [features] must be an array (as above);
    [Ok None] when empty. The first feature's [properties.toponym], else the
    first non-blank string of [properties.name] (an array), else [Ok None]. A
    value longer than 200 bytes counts as absent, as for Photon. *)

val geoplateforme_detail :
  near:Places.point ->
  commune:string ->
  Yojson.Safe.t ->
  (string option, error) result
(** A Géoplateforme lieu-dit payload ({!geoplateforme_lieu_dit}). [features]
    must be an array (as above); [Ok None] when empty. The first feature's name
    by the rule of {!geoplateforme_name} ([toponym], else the first non-blank
    [name]), kept when its [geometry.coordinates] are two finite numbers
    [[lon, lat]] within [detail_max_m +. 1e-3] of [near] ([Places.distance_m],
    inclusive) and it is not {!same_name} as [commune]; else [Ok None] (a
    feature without a usable point gives [Ok None], not an error).
    [properties.distance] is not read. *)

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

(* style: transparent: Geocoder.run and the tests match on it. *)
type 'a program =
  | Done of 'a
  | Get of request * (Yojson.Safe.t -> 'a program)
      (** A failure of the request (transport, status, not JSON) never reaches
          the continuation: the runner stops with its own error. *)
  | Try of request * (Yojson.Safe.t option -> 'a program)
      (** An optional request: any failure (refused, transport, status, not
          JSON) continues with [None]. *)

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

val reverse_ign : Places.point -> (named option, error) result program
(** « IGN en ligne », commune first. Outside {!in_france}: [Done (Ok None)], no
    request. Else [geoplateforme_commune] → {!geoplateforme_name}:
    - a payload that does not decode → [Done (Error e)], no second request;
    - no name, or one [Near.phrase] rejects → [Done (Ok None)], no lieu-dit
      request (the lieu-dit is only a detail of a commune);
    - a commune [c] → [Try geoplateforme_lieu_dit] →
      [geoplateforme_detail ~near:p ~commune:c]: [Ok d] →
      [Done (Ok (Some {name = <Near.phrase c>; detail = d}))]; a failed request
      or a payload that does not decode →
      [Done (Ok (Some {name = <Near.phrase c>; detail = None}))]: the detail is
      optional, the commune is kept. *)

val reverse_photon : Places.point -> (named option, error) result program
(** « Photon en ligne »: one [photon_reverse] request; {!photon_commune} → [c]
    ([None] → [Done (Ok None)]); [Near.phrase c] ([None] → [Done (Ok None)]);
    the detail by {!photon_detail} [~commune:c] on the same payload, [None] when
    it does not decode. A payload {!photon_commune} cannot read →
    [Done (Error e)]. Anywhere in the world. *)
