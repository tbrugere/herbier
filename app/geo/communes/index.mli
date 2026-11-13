(** The loaded packs, with a bounding box per commune: which commune holds a
    point. *)

module Places := Herbier_domain.Places

val edge_m : float
(** [Communes.edge_m]. *)

type t

val empty : t
val add : t -> Pack.t -> t
val remove : t -> Code.t -> t
val departements_of : t -> Code.t list
val find : t -> Places.point -> Pack.commune option

val name : t -> Places.point -> string option
(** All as [Communes]' functions of the same name. *)
