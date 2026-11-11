(** The pure geometry of 5e's pinch zoom: the content is drawn with
    [transform: translate(x, y) scale(scale)] from its top-left corner inside a
    [w] × [h] box of the same size. *)

type t = {scale : float; x : float; y : float}

val identity : t

val max_scale : float
(** [4.]. *)

val clamp : w:float -> h:float -> t -> t
(** Scale within [[1, max_scale]], and the offsets such that the scaled content
    still covers the box ([x] in [[w - w·scale, 0]], same for [y]). *)

val about : w:float -> h:float -> t -> cx:float -> cy:float -> ratio:float -> t
(** Multiplies the scale by [ratio] keeping the box point [(cx, cy)] still, then
    {!clamp}s. *)

val pan : w:float -> h:float -> t -> dx:float -> dy:float -> t
(** Moves by [(dx, dy)], then {!clamp}s. *)

val zoomed : t -> bool
(** Scale above 1 (by more than 1 %). *)

val settle : t -> t
(** [t] when {!zoomed}, else {!identity}: what a gesture leaves once every
    finger is up. *)
