(** Snap-point arithmetic of {!Widgets.Sheet}, pure so that test/ui checks it
    natively. Snap points are visible heights in px, strictly ascending. *)

val of_list : float list -> float array
(** [of_list snaps] is [snaps] as an array.

    @raise Invalid_argument if [snaps] is empty or not strictly ascending. *)

val clamp : float array -> float -> float
(** [clamp snaps y] is [y] bounded by the first and last snap points. *)

val nearest : float array -> float -> int
(** [nearest snaps y] is the index of the snap point closest to [y]; on a tie,
    the lower one. *)

val release : float array -> at:float -> speed:float -> rest_ms:float -> int
(** [release snaps ~at ~speed ~rest_ms] is the index a sheet released at visible
    height [at] settles on. [speed] is the gesture's last speed in px/ms, upward
    positive, and [rest_ms] how long the finger had been still when it lifted.
    The release point is projected 150 ms ahead along [speed] and the nearest
    snap point to that wins, so a fast flick can pass several; a finger that
    rested more than 80 ms before lifting projects nothing. *)
