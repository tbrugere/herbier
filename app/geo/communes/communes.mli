(** IGN commune boundaries for « IGN hors-ligne » (architecture §8): the
    Géoplateforme WFS requests of Admin Express COG carto (IGN, Licence Ouverte
    Etalab 2.0), their decoding and simplification into a pack, the pack's
    stored text, and an in-memory index answering « which commune holds this
    point ». Pure, no Brr; nothing here raises. *)

module Places := Herbier_domain.Places

val layer : string
(** ["ADMINEXPRESS-COG-CARTO.LATEST"] *)

(** {1 Départements} *)

(** A département code, checked once: the only kind of value that reaches the
    CQL filter and a pack's file name. *)
module Code : sig
  type t

  val of_string : string -> t option
  (** [Some] for two digits (["01"]…["95"]), ["2A"], ["2B"], three digits
      starting with ["97"] (["971"]…["976"]); [None] otherwise ([""], ["2a"],
      ["1"], ["20"], ["9a"], ["'"], ["68' or 1=1"]). No quote can get through.
  *)

  val to_string : t -> string
  val equal : t -> t -> bool

  val compare : t -> t -> int
  (** String order. *)
end

type departement = {code : Code.t; name : string}

val equal_departement : departement -> departement -> bool

val departements_request : Geocode.request
(** [Geocode.geoplateforme_wfs] of, in order: [SERVICE=WFS], [VERSION=2.0.0],
    [REQUEST=GetFeature], [OUTPUTFORMAT=application/json],
    [TYPENAMES=ADMINEXPRESS-COG-CARTO.LATEST:departement],
    [PROPERTYNAME=code_insee,nom_officiel], [SORTBY=code_insee], [COUNT=5000].
*)

val departements : Yojson.Safe.t -> (departement list, Geocode.error) result
(** [features] must be an array ([Unexpected {path = "/features"; _}]). Per
    feature: [properties.code_insee] passing {!Code.of_string} and a non-blank
    [properties.nom_officiel] ([Geocode.string]: trimmed, at most 200 bytes); a
    feature failing that is skipped (style 8.4). Sorted by code (string order),
    duplicates by code dropped (first kept). *)

val available : downloaded:Code.t list -> departement list -> departement list
(** The départements whose code is not in [downloaded], order kept: 4m's picker.
*)

(** {1 Packs} *)

type ring = (float * float) array
(** [(lon, lat)] vertices, not closed (the first vertex is not repeated), at
    least 3. *)

type commune = {
  insee : string;  (** [code_insee], 5 characters *)
  name : string;  (** [nom_officiel], non-blank *)
  polygons : ring list list;
      (** a MultiPolygon: each polygon an outer ring then its holes *)
}

type pack = {departement : Code.t; communes : commune list}
(** [communes] sorted by [insee], non-empty. *)

val equal_pack : pack -> pack -> bool
(** Structural, coordinates compared exactly (they are on the 1e-5 grid). *)

val tolerance_m : float
(** [20.]: the Douglas–Peucker tolerance of {!pack_of_payload}. *)

val edge_m : float
(** [50.]: how far outside every polygon {!find} still takes the nearest
    commune. *)

val communes_request : departement:Code.t -> Geocode.request
(** [Geocode.geoplateforme_wfs] of, in order: [SERVICE=WFS], [VERSION=2.0.0],
    [REQUEST=GetFeature], [OUTPUTFORMAT=application/json],
    [TYPENAMES=ADMINEXPRESS-COG-CARTO.LATEST:commune],
    [PROPERTYNAME=code_insee,nom_officiel,geometrie], [SORTBY=code_insee],
    [COUNT=5000], [CQL_FILTER=code_insee_du_departement='<code>']. *)

val simplify : tolerance_m:float -> ring -> ring
(** Douglas–Peucker on a closed ring, distances in metres in the local
    equirectangular projection about the ring's first vertex
    ([x = Δlon·cos(lat₀)·m], [y = Δlat·m], [m = π·Places.earth_radius_m/180]
    metres per degree). The ring is split at the vertex farthest from its first
    vertex and each half simplified as a polyline, then joined. Guarantees:
    - every vertex of the input is within [tolerance_m] (+1 m of rounding) of
      the output's boundary;
    - the output's vertices are a subsequence of the input's, first vertex kept;
    - an output of fewer than 3 vertices is replaced by the input (tiny islets
      survive);
    - an input of fewer than 4 vertices is returned unchanged. *)

val pack_of_payload :
  departement:Code.t -> Yojson.Safe.t -> (pack, Geocode.error) result
(** A WFS GetFeature payload of {!communes_request}:
    - [features] not an array →
      [Unexpected {path = "/features"; expected = "array"}];
    - [numberMatched] an int greater than the length of [features] →
      [Unexpected {path = "/numberMatched"; expected = "all features in one
       page"}] (truncated: half a département is never stored);
    - 5000 features or more (the request's [COUNT], so possibly truncated
      whatever [numberMatched] says) →
      [Unexpected {path = "/features"; expected = "fewer than COUNT features"}];
    - per feature: [properties.code_insee] (5 characters), a non-blank
      [properties.nom_officiel] ([Geocode.string]), [geometry.type]
      ["MultiPolygon"] or ["Polygon"] with numeric (int or float), finite
      [[lon, lat]] pairs; a feature failing any of these is skipped (style
      §8.4). Each ring: closing vertex dropped, coordinates rounded to 1e-5°,
      consecutive duplicates removed, a ring left with fewer than 3 vertices
      dropped (a polygon without its outer ring dropped, a commune without
      polygons dropped), then {!simplify} at {!tolerance_m};
    - no commune left →
      [Unexpected {path = "/features"; expected = "at least one commune"}] (an
      unknown code, or an empty answer).

    Communes sorted by [insee]. *)

val to_string : pack -> string
(** The stored file, compact JSON:
    [{"format":1,"layer":"ADMINEXPRESS-COG-CARTO.LATEST","departement":"90",
     "tolerance_m":20,"communes":[{"insee":"90001","name":"Andelnans",
     "polygons":[[[x0,y0,x1,y1,…],[hole…]]]}]}] with [x], [y] the integers
    [round(lon·1e5)], [round(lat·1e5)] (flat per ring, ring not closed). UTF-8
    names as is. *)

val of_string : string -> (pack, Geocode.error) result
(** Inverse of {!to_string}: [of_string (to_string p) = Ok p] for every [p]
    produced by {!pack_of_payload}. [Not_json] for bad JSON;
    [Unexpected {path = "/format"; expected = "1"}] for another format;
    [Unexpected {path = "/departement"; expected = "a département code"}] for a
    [departement] failing {!Code.of_string}; [Unexpected] at the first malformed
    field (a ring of odd length or of fewer than 6 numbers included). A stored
    file is ours: nothing is skipped. *)

(** {1 Index} *)

type t
(** The loaded packs, with a bounding box per commune. *)

val empty : t

val add : t -> pack -> t
(** Replaces a pack of the same département. *)

val remove : t -> Code.t -> t
(** By département code; an absent code leaves [t] unchanged. *)

val departements_of : t -> Code.t list
(** The codes of the packs, sorted. *)

val find : t -> Places.point -> commune option
(** A non-finite coordinate → [None]. Else, over every pack in département order
    and communes in [insee] order (a commune's bounding box skips it early):
    + the first commune one of whose polygons contains the point (even–odd rule
      over the outer ring and its holes: a point in a hole is not in that
      polygon); a point exactly on an edge counts for at most one side
      (half-open ray casting);
    + else the commune whose boundary (any ring) is nearest, if within {!edge_m}
      (slivers left by simplification between neighbours, and a point just
      outside a downloaded département's outer edge, even in a département not
      downloaded or abroad: simplification moves that edge too, so a point truly
      inside can land there);
    + else [None]. *)

val name : t -> Places.point -> string option
(** The phrase of [find t p]'s commune [c]: [Near.inside c.name] when one of its
    polygons contains the point (« À Belfort », « À Éloie »),
    [Near.phrase c.name] when it is only the nearest within {!edge_m} (« Près de
    Belfort »): there, containment is not known. *)
