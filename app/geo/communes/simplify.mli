(** Douglas–Peucker simplification of a ring, and the local metric projection it
    measures in. *)

val metres_per_degree : float
(** [π·Places.earth_radius_m/180]. *)

val segment_distance : float * float -> float * float -> float * float -> float
(** [segment_distance p a b]: the distance from [p] to the segment [a]–[b], all
    in one local metric projection (metres). *)

val simplify : tolerance_m:float -> Pack.ring -> Pack.ring
(** [Communes.simplify]. *)
