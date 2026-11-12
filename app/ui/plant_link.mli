(** The plant record after linking it to a GBIF taxon. Pure. *)

val apply :
  at:Ptime.t ->
  Herbier_domain.Plant.t ->
  Herbier_refs.Sources.Gbif.Taxon.t ->
  Herbier_domain.Plant.t
(** [gbif_key = Some taxon.key]; [scientific_name = Some] the taxon's
    [canonical_name], else its [scientific_name];
    [authorship = taxon.authorship]; [updated_at = at]. Display name, aliases,
    notes, cover, dates otherwise unchanged. *)

val retires_references :
  Herbier_domain.Plant.t -> Herbier_refs.Sources.Gbif.Taxon.t -> bool
(** The plant had a gbif_key other than the taxon's. *)
