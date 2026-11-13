(** A pack: the communes of one département, as decoded from the WFS ({!Wfs})
    and stored ({!Pack_file}). *)

val layer : string
(** ["ADMINEXPRESS-COG-CARTO.LATEST"] *)

type ring = (float * float) array
(** [(lon, lat)] vertices, not closed, at least 3. *)

type commune = {insee : string; name : string; polygons : ring list list}
type t = {departement : Code.t; communes : commune list}

val equal : t -> t -> bool
(** Structural, coordinates compared with [Float.equal]. *)

val tolerance_m : float
(** [20.]: the Douglas–Peucker tolerance of a pack. *)

val all : ('a -> 'b option) -> 'a list -> 'b list option
(** [Some] of every result when [f] gives [Some] for each item, else [None].
    Tail-recursive: a ring has thousands of vertices. *)
