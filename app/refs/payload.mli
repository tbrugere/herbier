(** The [payload] of one [reference] row ([Reference.t.payload], architecture
    §6): a JSON object with one member per call made to the source, holding that
    call's body as returned, pruned to the fields the decoders of [Sources]
    read. A member is absent when its call was not made or failed (the row's
    [status] says which). Pure; never raises. *)

module Source := Herbier_domain.Reference.Source

type part =
  | Gbif_species  (** [Sources.Gbif.species], member ["species"]. *)
  | Gbif_vernacular_names  (** ["vernacular_names"] *)
  | Gbif_distributions  (** ["distributions"] *)
  | Gbif_occurrence_count  (** ["occurrence_count"] *)
  | Plantnet_media
      (** [Sources.Gbif.plantnet_media] (fetched from GBIF, cited as Pl@ntNet),
          member ["media"]. *)
  | Wikidata_search  (** ["search"] *)
  | Wikidata_entity  (** ["entity"] *)
  | Wikipedia_summary  (** ["summary"]: fr, or en when fr has no page. *)

val all : part list
(** Declaration order. *)

val source : part -> Source.t
(** [Gbif] for the four [Gbif_*], [Plantnet], [Wikidata] for both [Wikidata_*],
    [Wikipedia]. *)

val name : part -> string
(** The member name above. *)

val parts : Source.t -> part list
(** The parts of that source's row, in [all] order; [[]] for a source without
    parts (powo, ipni, taxref, tela, eppo, inat). *)

(** {1 Building}

    One builder per fetched source, so a payload never mixes sources. Each
    applies {!prune} to every body and returns an object whose members are the
    given parts, in [all] order, [None] ones omitted; all [None] gives
    [`Assoc []]. *)

val gbif :
  species:Yojson.Safe.t option ->
  vernacular_names:Yojson.Safe.t option ->
  distributions:Yojson.Safe.t option ->
  occurrence_count:Yojson.Safe.t option ->
  Yojson.Safe.t

val plantnet : media:Yojson.Safe.t option -> Yojson.Safe.t

val wikidata :
  search:Yojson.Safe.t option -> entity:Yojson.Safe.t option -> Yojson.Safe.t

val wikipedia : summary:Yojson.Safe.t option -> Yojson.Safe.t

val prune : part -> Yojson.Safe.t -> Yojson.Safe.t
(** What the builders apply to each body. Identity for [Gbif_species],
    [Gbif_occurrence_count], [Wikidata_search], [Wikipedia_summary] (small).
    Otherwise keeps only:
    - [Gbif_vernacular_names]: root [results], [endOfRecords], [count]; in each
      object of [results]: [vernacularName], [language], [source], [country];
    - [Gbif_distributions]: root as above; per result: [locationId], [locality],
      [country], [status], [establishmentMeans], [threatStatus], [source];
    - [Plantnet_media]: root as above; per result: [key], [references], [media];
      per object of [media]: [type], [identifier], [title], [license],
      [rightsHolder], [creator], [source];
    - [Wikidata_entity]: root [entities] and [error] (whole); per entity: [id],
      [missing], [claims] restricted to P846, P5037, P961, P3186, P3105, P3031,
      P3151, P1843 with each statement reduced to [rank] and [mainsnak] (whole),
      [sitelinks] restricted to frwiki, enwiki, dewiki, itwiki (whole sitelink
      objects).

    Members keep their order; values are not otherwise touched (an [`Intlit]
    occurrence key stays an [`Intlit]). A body or element not of the expected
    shape (root not an object, [results] not an array, an element not an object,
    [entities] not an object, …) is kept as given at that level, so the decoder
    reports the same error it would on the raw body: for every part, decoding
    [prune part body] gives the same [Ok] value or the same [Error] as decoding
    [body]. *)

(** {1 Reading} *)

val get : part -> Yojson.Safe.t -> Yojson.Safe.t option
(** The member [name part] of a payload object; [None] when absent, [`Null], or
    when the payload is not an object. *)
