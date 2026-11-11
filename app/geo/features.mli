(** GeoJSON the map shows (architecture §8). Pure: domain + yojson. Positions
    are [[lon, lat]] (GeoJSON order). *)

module Observation = Herbier_domain.Observation
module Places = Herbier_domain.Places

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

type bounds = {south : float; west : float; north : float; east : float}

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
