(** The species page's links: a stored plant ref when one is valid for its
    source, else one derived from the reference payloads. *)

module Reference := Herbier_domain.Reference

type t = {source : Reference.Source.t; url : string}

val link_order : Reference.Source.t list
(** [Projection.link_order]. *)

val links :
  plant_refs:Reference.Plant_ref.t list ->
  taxon:Sources.Gbif.Taxon.t option ->
  entity:Sources.Wikidata.Entity.t option ->
  summary:Sources.Wikipedia.t option ->
  t list
(** [Projection.t]'s [links]. *)
