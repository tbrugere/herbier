(** « Dans ma collection »: one of my live plants has the proposal's GBIF key.
    Pure. *)

type t = {plant : Herbier_domain.Plant.t; observations : int}

val equal : t -> t -> bool

val find :
  current:Herbier_domain.Ids.Plant_id.t option ->
  plants:Herbier_domain.Plant.t list ->
  observations:Herbier_domain.Observation.t list ->
  int option ->
  t option
(** [find ~current ~plants ~observations gbif]: [gbif = None] → [None]. Else the
    first of [plants], in the given order, with [deleted_at = None],
    [gbif_key = gbif] and [Some id <> current]; [observations] = how many of
    [observations] have [deleted_at = None] and [plant_id = Some plant.id] (0
    possible). None such → [None]. Never raises. *)
