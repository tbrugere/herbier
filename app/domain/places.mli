(** Places: derived, never stored (architecture §2). Great-circle distance, the
    500 m clustering behind the map's places (handoff 4b) and "Vues ici" (4d),
    and the place-name rule of the Journal's day headers (4c). Pure: no I/O, no
    clock, no randomness. Results do not depend on the order of the input list,
    provided distinct records have distinct [(at, id)] (the store returns one
    row per id).

    Means of points are plain means of degrees: there is no antimeridian or
    polar handling, so a group straddling lon ±180 gets a centroid on the far
    side of the globe. *)

type point = {lat : float; lon : float}
(** WGS84 degrees. *)

val of_position : Observation.position -> point
(** Drops [accuracy_m]. *)

val position_point : Observation.t -> point option
(** The placeable rule of {!cluster}: [Some {lat; lon}] for a live observation
    ([deleted_at = None]) with [position = Some p] and finite [p.lat] and
    [p.lon]; [None] otherwise. Never raises. *)

val compare_obs : Observation.t -> Observation.t -> int
(** The order of {!cluster} members: ascending [at], ties by
    [Ids.Observation_id.compare] on [id]. *)

val earth_radius_m : float
(** Mean Earth radius used by [distance_m]: [6_371_000.]. *)

val radius_m : float
(** Radius of a place: [500.]. *)

val distance_m : point -> point -> float
(** Great-circle (Haversine) distance in metres on a sphere of radius
    [earth_radius_m]. Symmetric, [0.] for equal points, never negative, at most
    [Float.pi *. earth_radius_m]; antipodes give that value, not [nan] (the
    haversine term is clamped to [[0, 1]]). [lon = 180.] and [lon = -180.] are
    the same meridian. A [nan] coordinate gives [nan]. Never raises. *)

val within : point -> point -> bool
(** [within a b] is [distance_m a b <= radius_m +. 1e-3]: inclusive, with a 1 mm
    allowance so that a point computed at exactly 500 m is within despite
    floating-point rounding. [false] when either point has a [nan] coordinate.
*)

type cluster = {
  centroid : point;
      (** Arithmetic mean of the members' latitudes and of their longitudes (no
          antimeridian handling, see above). *)
  members : Observation.t list;
      (** Never empty. Ascending by [at], ties by [Ids.Observation_id.compare]
          on [id]. *)
}

val cluster : Observation.t list -> cluster list
(** Groups observations into places. Placeable observations are taken in
    ascending order of [at] (ties by id); each joins the existing cluster whose
    current centroid is nearest among those [within] its point (an exact tie
    goes to the earliest-created cluster), or starts a new one. There is no
    second pass, so a later member may pull the centroid more than [radius_m]
    away from an early one.

    Places are stable only under appends in [at] order: a new observation with
    the latest [at] extends or creates a place and leaves the others as they
    were, but one with an earlier [at] (an imported photo, an edited time, a row
    synced late) replays the pass from that point, and later places can split,
    merge or move.

    Observations that cannot be placed are in no cluster: soft-deleted ones
    ([deleted_at = Some _]), those with [position = None], and those whose [lat]
    or [lon] is not finite ([nan], [infinity]). Clusters come in ascending order
    of their first member. [[]] for an empty or all-unplaceable input. Every
    placeable observation is in exactly one cluster; the same record given twice
    is two members. Never raises. *)

type label =
  | Named of string  (** a user-given [place_label] *)
  | Derived of string  (** a reverse-geocoded [place_derived] *)
  | Coordinates of point
      (** mean of the placeable positions (no antimeridian handling) *)

val label : Observation.t list -> label option
(** Name of a group of observations: a Journal day (4c), or a cluster's
    [members] (4b sheet title). Soft-deleted observations are ignored. Then, in
    order:
    - [Named s]: [s] is the most frequent [place_label] among the observations
      that have a non-blank one;
    - else [Derived s]: likewise over [place_derived];
    - else [Coordinates c]: [c] is the arithmetic mean of the placeable
      positions (the same placeable rule as [cluster]);
    - else [None]: empty list, or nothing labelled and nothing placeable.

    Labels are trimmed with [String.trim] before use; an empty trimmed label
    counts as absent; trimmed labels are compared with [String.equal]
    (case-sensitive) and the trimmed string is returned. A frequency tie goes to
    the label whose earliest observation (by [at], then id) comes first. Never
    raises. *)
