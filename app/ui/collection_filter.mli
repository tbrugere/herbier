(** The pure part of the Collection grid's content: observation counts per plant
    and the tag filter that requires every selected tag (Journal's too). *)

module Plant_id = Herbier_domain.Ids.Plant_id
module Tag_id = Herbier_domain.Ids.Tag_id

type counts
(** Observations per plant. *)

val counts : Herbier_domain.Observation.t list -> counts
(** One pass over the observations; one without a plant counts for none. *)

val count : counts -> Plant_id.t -> int
(** [0] for a plant with no observation. *)

val has_all_tags : tagged:Plant_id.t list list -> Plant_id.t -> bool
(** [tagged] holds, for each selected tag, the plants that have it: [true] when
    the plant is in every one of them, so [true] when no tag is selected. *)

val tagged :
  Herbier_domain.Tag.Plant_tag.t list -> Tag_id.t list -> Plant_id.t list list
(** [tagged links tags]: for each selected tag, in order, the plants that
    [links] ({!Herbier_store.Tags.links}) put it on; the [tagged] of
    {!has_all_tags}. *)

val toggle_tag : Tag_id.t -> Tag_id.t list -> Tag_id.t list
(** Removes the tag from the selection when it is in it, adds it otherwise. *)
