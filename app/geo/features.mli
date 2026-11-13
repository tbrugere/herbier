(** GeoJSON the map shows (architecture §8). Pure: domain + yojson. Positions
    are [[lon, lat]] (GeoJSON order). *)

module Observation = Herbier_domain.Observation
module Places = Herbier_domain.Places
module Observation_id = Herbier_domain.Ids.Observation_id

val empty : Yojson.Safe.t
(** [{"type":"FeatureCollection","features":[]}] *)

(** What a point shows; {!Style} colours points by it. *)
type kind =
  | Identified  (** [plant_id = Some _] *)
  | To_identify  (** [plant_id = None] *)

val kind_key : string
(** ["kind"]: the feature property holding {!kind_to_string}. *)

val kind_to_string : kind -> string
(** ["identified"], ["to_identify"]. *)

val observations : Observation.t list -> Yojson.Safe.t
(** A FeatureCollection with one Point feature per observation that
    {!Places.position_point} places, in {!Places.compare_obs} order (so the
    newest is drawn on top), whatever the input order. Feature:
    [{"type":"Feature","geometry":{"type":"Point","coordinates":[lon,lat]},
     "properties":{"id":<uuid>,"kind":k}}], [k] the observation's {!kind};
    exactly those two properties. Never raises; never emits NaN or infinity. *)

type bounds = Herbier_domain.Bbox.t = {
  south : float;
  west : float;
  north : float;
  east : float;
}

val bounds : Observation.t list -> bounds option
(** Min/max of the placeable positions; [None] when none is placeable. No
    antimeridian handling (same as {!Places}). *)

val circle : center:Places.point -> radius_m:float -> steps:int -> Yojson.Safe.t
(** The accuracy circle (handoff 4h; [radius_m] in metres): a FeatureCollection
    with one Polygon feature (properties [{}]) whose single ring has [steps + 1]
    positions, the last equal to the first, each vertex the destination point at
    [radius_m] from [center] on the sphere of [Places.earth_radius_m] at
    bearings [360 * i / steps] degrees from north, i = 0..steps-1. {!empty} when
    [radius_m] is not finite or [<= 0.], [steps < 3], or a [center] coordinate
    is not finite. Never raises. *)

val circle_steps : int
(** The number of vertices of the accuracy circle drawn on a map
    ([Map.set_accuracy]) and boxed by {!circle_bounds}. *)

val circle_bounds : center:Places.point -> radius_m:float -> bounds option
(** The box of {!circle} [~center ~radius_m ~steps:circle_steps]: min/max of the
    ring's latitudes ([south], [north]) and longitudes ([west], [east]),
    computed from the same vertices, so the drawn circle is inside it.
    Longitudes are not brought back into [-180, 180]: across the antimeridian
    [east] passes 180 and the box stays contiguous, as fitBounds wants it.
    [None] exactly when {!circle} gives {!empty} (radius not finite or [<= 0.],
    a coordinate not finite). Never raises. *)

val accuracy_bounds : Observation.position -> bounds option
(** What 4h's mini-map frames. [None] when [lat] or [lon] is not finite. With
    [accuracy_m = Some r], [r] finite and [> 0.]: {!circle_bounds} at the point
    with radius [r]. Otherwise ([None], [0.], negative, NaN, infinity) the
    degenerate box at the point ([south = north = lat], [west = east = lon]).
    Never raises. *)

val focus : Places.point option -> Yojson.Safe.t
(** 4h's point. [None], or a non-finite coordinate: {!empty}. [Some p]: a
    FeatureCollection with one feature
    [{"type":"Feature","geometry":{"type":"Point","coordinates":[lon,lat]},
     "properties":{}}]. *)

(** {1 Places (handoff 4b)} *)

type place = {
  key : Observation_id.t;
      (** id of the cluster's first member ({!Places.compare_obs} order): stable
          under appends in time order, the place's id on the map and in the 4b
          state *)
  cluster : Places.cluster;
      (** the whole place: its name, what « Renommer » writes *)
  shown : Observation.t list;
      (** members that pass the filters, in [cluster.members] order; never empty
          in {!places}' result *)
}

val places :
  keep:(Places.cluster -> Observation.t -> bool) ->
  Observation.t list ->
  place list
(** {!Places.cluster} of the whole list, then for each cluster its members
    satisfying [keep cluster]; clusters with no such member are dropped. Order:
    {!Places.cluster}'s. [keep] gets the member's own cluster (so a caller can
    match on the place's name) and must be pure. Never raises (unless [keep]
    does). *)

val find : place list -> Observation_id.t -> place option
(** The place whose [cluster.members] (not only [shown]) holds an observation
    with that id; [None] otherwise. *)

val count_key : string
(** ["count"] *)

val identified_key : string
(** ["identified"] *)

val role_key : string
(** ["role"] *)

val west_key : string
(** ["west"] *)

val south_key : string
(** ["south"] *)

val east_key : string
(** ["east"] *)

val north_key : string
(** ["north"] *)

val place_points : place list -> Yojson.Safe.t
(** A FeatureCollection, one Point per place in the given order, at
    [cluster.centroid], properties exactly:
    [{"id": <key uuid>, "count": <length shown>, "identified": <shown members
     with a plant>, "west": w, "south": s, "east": e, "north": n}] (the
    {!count_key} … {!north_key} names) where the four floats are {!bounds} of
    [shown]. A place whose [shown] is empty is skipped. No NaN or infinity
    emitted (a place with a non-finite centroid is skipped). *)

val selection : place option -> Yojson.Safe.t
(** [None]: {!empty}. [Some p]: a FeatureCollection whose first feature is a
    Point at [p.cluster.centroid] with properties
    [{"id": <key>, "role": "place"}], followed by one Point per placeable member
    of [p.shown] in {!Places.compare_obs} order with
    [{"id": <observation id>, "role": "member"}]. *)

type hit =
  | Group of bounds  (** a MapLibre cluster of places: its aggregated bounds *)
  | Member of Observation_id.t
      (** a place point (its key), a member point or a selection point *)

val hit : Yojson.Safe.t -> hit option
(** Decodes the properties of a tapped feature: an object with ["cluster": true]
    and numeric (int or float), finite ["west"], ["south"], ["east"], ["north"]
    is [Group]; [cluster:true] with a bound missing or not finite is [None];
    otherwise an object with a string ["id"] that [Observation_id.of_string]
    accepts is [Member]; anything else [None]. Never raises. *)
