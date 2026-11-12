(** What tapping a reference row of 4i / 4k / 5c does, per entry mode of
    [screens/resolve.ml]. Pure. *)

type mode =
  | Browse  (** 4i [Search]: the collection lens. *)
  | Attach  (** 4k [Identify], 5c [Change]: the observation goes to a plant. *)
  | Relink  (** 4i [Link_plant]: 4g « Lier », 5a « Changer › ». *)

type action =
  | Inert  (** The current plant's species: greyed, no action. *)
  | Open of Herbier_domain.Plant.t
      (** « Ouvrir › »: the fiche of the plant that already has the species. *)
  | Attach_to of Herbier_domain.Plant.t
      (** « Lier › »: the observation joins that plant, no new plant. *)
  | Create
      (** « + »: a new plant linked to the taxon (4i: then its fiche; 4k/5c:
          then the observation joins it). *)
  | Link_this  (** « + »: the plant of the mode is linked to the taxon. *)

val equal_action : action -> action -> bool

val action :
  mode ->
  current:Herbier_domain.Ids.Plant_id.t option ->
  plants:Herbier_domain.Plant.t list ->
  Herbier_refs.Sources.Gbif.Taxon.t ->
  action
(** [matching] = the live [plants] (given order; deleted ones ignored) whose
    [gbif_key] is [Some taxon.key], or [Some a] when
    [taxon.accepted_key = Some a].
    - [current] is among [matching] → [Inert] (every mode);
    - [Browse]: first of [matching] → [Open p], none → [Create];
    - [Attach]: first of [matching] → [Attach_to p], none → [Create];
    - [Relink]: [Link_this] (two plants may share a taxon). *)

val other_owner :
  current:Herbier_domain.Ids.Plant_id.t option ->
  plants:Herbier_domain.Plant.t list ->
  Herbier_refs.Sources.Gbif.Taxon.t ->
  Herbier_domain.Plant.t option
(** For [Relink] rows' « Aussi dans ma collection : X »: the first of [matching]
    that is not [current]. *)
