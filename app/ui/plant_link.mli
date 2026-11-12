(** The plant record after linking it to a GBIF taxon. Pure. *)

val apply :
  at:Ptime.t ->
  ?name:string ->
  Herbier_domain.Plant.t ->
  Herbier_refs.Sources.Gbif.Taxon.t ->
  Herbier_domain.Plant.t
(** [gbif_key = Some taxon.key]; [scientific_name = Some] the taxon's
    [canonical_name], else its [scientific_name];
    [authorship = taxon.authorship]; [updated_at = at]. Notes, cover, dates
    otherwise unchanged.

    With [name], when [String.trim name <> ""] and the plant is a free-name one
    ([scientific_name = None]): [display_name = String.trim name]; the old
    display name (trimmed) is prepended to [aliases] unless it equals the new
    name or an existing alias; an existing alias equal to the new name is
    removed; other aliases keep their order. Comparisons fold ASCII case, as
    {!Plant_form}. A plant that already has a [scientific_name] (a relink) keeps
    its display name and aliases whatever [name] says. *)

val display_name : Herbier_refs.Resolve.Candidate.t -> string
(** The first of [french], else the taxon's [canonical_name], else its
    [scientific_name]. *)

val create :
  id:Herbier_domain.Ids.Plant_id.t ->
  at:Ptime.t ->
  name:string ->
  Herbier_refs.Sources.Gbif.Taxon.t ->
  Herbier_domain.Plant.t
(** [apply ~at (Plant.v ~id ~at name) taxon]: a new plant named [name], already
    linked; [created_at = updated_at = at], no alias. *)

val retires_references :
  Herbier_domain.Plant.t -> Herbier_refs.Sources.Gbif.Taxon.t -> bool
(** The plant had a gbif_key other than the taxon's. *)
