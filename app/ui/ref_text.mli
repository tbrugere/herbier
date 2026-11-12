(** Texts of 4f's reference block. Pure. *)

val source_name : Herbier_domain.Reference.Source.t -> string
(** "GBIF", "Wikidata", "Wikipédia", "POWO", "IPNI", "INPN" (taxref), "Tela
    Botanica", "EPPO", "iNaturalist", "Pl@ntNet". *)

val names_line : Herbier_refs.Projection.vernacular -> string
(** The names joined with [", "] (the language code is rendered apart, bold). *)

val names_source_line :
  family:string option -> Herbier_domain.Reference.Source.t list -> string
(** The « Noms » sub-line: ["Plantaginaceae · GBIF, Wikidata"]; without a
    family, the sources alone; [""] with neither. *)
