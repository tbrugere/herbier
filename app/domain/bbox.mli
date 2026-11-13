(** A bounding box in degrees, as MapLibre's fitBounds takes it. *)

type t = {south : float; west : float; north : float; east : float}

val equal : t -> t -> bool
(** Field-wise [Float.equal] ([nan] equals [nan]). *)

val of_point : Places.point -> t
(** The degenerate box at the point. *)

val extend : t -> Places.point -> t
(** The box grown to the point, with [Float.min] and [Float.max]: a [nan]
    coordinate makes that side [nan]. *)

val of_points : Places.point list -> t option
(** The smallest box holding every point; [None] for no point. Points are not
    filtered: a [nan] or infinite coordinate goes into the box as {!extend}
    says. *)

val contains : ?dlat:float -> ?dlon:float -> t -> Places.point -> bool
(** Whether the point is in the box grown by [dlat] and [dlon] degrees (default
    [0.]) on each side, edges included. [false] when a coordinate of the point
    or a side of the box is [nan]. *)
