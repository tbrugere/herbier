(** The pure part of the Collection grid's content: observation counts per plant
    and the filter that requires every selected tag. *)

module Plant_id = Herbier_domain.Ids.Plant_id

type counts
(** Observations per plant. *)

val counts : Herbier_domain.Observation.t list -> counts
(** One pass over the observations; one without a plant counts for none. *)

val count : counts -> Plant_id.t -> int
(** [0] for a plant with no observation. *)

val has_all_tags : tagged:Plant_id.t list list -> Plant_id.t -> bool
(** [tagged] holds, for each selected tag, the plants that have it: [true] when
    the plant is in every one of them, so [true] when no tag is selected. *)
