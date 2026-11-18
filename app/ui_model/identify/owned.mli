(** « Dans ma collection »: one of my live plants has the proposal's GBIF key.
    Pure. *)

type t = {plant : Herbier_domain.Plant.t; observations : int}

val equal : t -> t -> bool

val has_key : keys:int list -> Herbier_domain.Plant.t -> bool
(** A live plant ([deleted_at = None]) whose [gbif_key] is one of [keys]: the
    one rule for « this species is a plant of mine », here (6c, on the
    proposal's id alone) and in {!Choice.owner} (6e, on {!Choice.keys}). *)

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
