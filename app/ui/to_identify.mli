(** 4k's « À IDENTIFIER · i / n » and « Suivante › ». *)

type position = {
  index : int;
  total : int;
  next : Herbier_domain.Observation.t option;
}
(** [index] counts from 1. [next] is the observation after the current one,
    wrapping to the first; [None] when the current one is the only one. *)

val position :
  Herbier_domain.Observation.t ->
  Herbier_domain.Observation.t list ->
  position option
(** Where the observation (by id) is in the list; [None] when it is not there
    (already identified). *)
