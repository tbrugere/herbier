(** Reference rows of one plant → the fields of the species page's reference
    block (handoff 4f, [ReferenceSnapshot]; architecture §6). Pure, total: a
    part that is missing or fails to decode degrades its fields only (style
    §8.4); one that fails to decode, or sits in a payload that is not a JSON
    object, is reported in [problems]. Never raises. *)

module Reference := Herbier_domain.Reference

type 'a cited = {value : 'a; sources : Reference.Source.t list}
(** A value and the sources it came from, in [Reference.Source.all] order,
    without duplicates ("Toute donnée cite sa source"). *)

module Lang : sig
  type t = Fr | En | De | It

  val all : t list
  (** [[Fr; En; De; It]]: the order of the [vernacular] field. *)

  val to_string : t -> string
  (** ["fr"], ["en"], ["de"], ["it"]. *)
end

type vernacular = {lang : Lang.t; names : string list}
(** [names] has 1 to 3 names. *)

type origin = {native : string list; introduced : string list}
type link = {source : Reference.Source.t; url : string}
type problem = {part : Payload.part; error : Decode.error}

type t = {
  fetched_at : Ptime.t option;
      (** The oldest [fetched_at] among the rows used that are not [Failed] (a
          failed row brought nothing to date); [None] with none. *)
  taxon : Sources.Gbif.Taxon.t cited option;  (** [Gbif_species]; [[Gbif]]. *)
  vernacular : vernacular list cited option;
      (** fr, en, de, it in that order, languages without a name omitted; [None]
          when all are empty. *)
  origin : origin cited option;  (** [[Gbif]] (WCVP rows). *)
  red_list : string cited option;
      (** The global IUCN category as GBIF gives it (["LEAST_CONCERN"]);
          [[Gbif]]. *)
  toxicity : string cited option;
      (** One sentence about toxicity, quoted as written, not a verdict: a
          negated one ("n'est pas toxique") is kept; [[Wikipedia]]. *)
  organ_photos : Sources.Gbif.Image.t list cited option;
      (** At most one per organ, in [Reference.Organ.all] order (flower, leaf,
          fruit, habit), each with [organ = Some _]; [[Plantnet]]; [None] when
          empty. Each [url] is unchecked, as in [Sources.Gbif.Image.t]: a caller
          checks its host before using it as [src] or downloading it. *)
  links : link list;  (** In the order of {!link_order}; may be empty. *)
  problems : problem list;
      (** In [Payload.all] order of the failing parts. [Gbif_occurrence_count]
          and [Wikidata_search] are decoded only for this list: no field reads
          them. *)
}

val project :
  references:Reference.t list -> plant_refs:Reference.Plant_ref.t list -> t
(** Rows with [deleted_at = Some _] are ignored; of two live rows of one source
    the first in the list wins (the store's unique key makes it impossible).
    Rows of sources without parts ({!Payload.parts} [= []]) are ignored. A row's
    [status] is not read: whatever parts its payload holds are used.
    [plant_refs] only supply links.

    A row whose [payload] is not a JSON object gives an
    [Unexpected {path = ""; expected = "object"}] problem for each of its
    source's parts.

    Rules:
    - vernacular: GBIF vernacular rows of language [fra], [eng], [deu], [ita]
      (their name split on [','], pieces trimmed, blank ones dropped), then
      Wikidata P1843 names of language exactly [fr], [en], [de], [it] (trimmed,
      blank dropped), each piece a vote; per language, names grouped by
      [String.lowercase_ascii] and spelled as their first vote; groups by vote
      count descending, ties by first vote; the first 3 kept;
    - origin: GBIF distribution rows of WCVP with a [locality] and a status
      [None], ["PRESENT"], ["COMMON"], ["RARE"] or ["IRREGULAR"]; native when
      [establishment_means] is [None] or ["NATIVE"], introduced when it is
      ["INTRODUCED"], ["NATURALISED"], ["INVASIVE"] or ["MANAGED"], else
      neither; payload order, duplicates dropped;
    - red list: the first IUCN Red List row without a [country] with a
      [threat_status];
    - toxicity: from a [Standard] summary only, the first sentence of [extract]
      (cut after ['.'], ['!'] or ['?'] followed by a space or a newline, except
      a ['.'] after a lone capital such as the author initial in ["L. "], and at
      every newline) whose lowercase (ASCII and Latin-1 capitals folded)
      contains ["toxique"], ["toxic"], ["vénéneu"] or ["poison"], trimmed; else
      the [description] when it matches;
    - organ photos: per organ, the first Pl@ntNet image of that organ;
    - links: per source of {!link_order}, the [url] of the first live plant ref
      of that source whose [url] is https, has no whitespace or control
      character, and points at that source ({!Herbier_domain.Link.classify}
      gives that source's constructor, [Inpn] for [Taxref]; for EPPO, Wikidata
      and IPNI, which it does not know, the host is [gd.eppo.int],
      [www.wikidata.org] or [m.wikidata.org], [www.ipni.org] or [ipni.org]);
      else a URL derived from the ids (GBIF key, the [Standard] summary's https
      page URL that classifies as Wikipedia, the entity's POWO, TaxRef, Tela,
      iNaturalist and EPPO ids), else none. *)

val link_order : Reference.Source.t list
(** [Gbif; Plantnet; Wikipedia; Powo; Taxref; Tela; Inat; Eppo; Wikidata; Ipni]:
    the handoff's row (GBIF, Pl@ntNet, Wikipédia, POWO, INPN, Tela) then the
    others. Every source appears once. *)

(** The handoff's [ReferenceSnapshot] fields (altitude dropped, architecture
    §6): a field not {!filled} is a row 4f hides. *)
module Field : sig
  type t =
    | Vernacular
    | Family
    | Life_form
    | Native_range
    | Introduced_range
    | Fr_status
    | Fr_protection
    | Red_list
    | Flowering_months
    | Habitat
    | Ecology
    | Toxicity
    | Organ_photos
    | Links

  val all : t list
  (** Declaration order: 14 fields. *)

  val to_string : t -> string
  (** snake_case of the constructor (["life_form"]). *)
end

val filled : t -> Field.t -> bool
(** [Vernacular]: [vernacular <> None]; [Family]: the taxon has a family;
    [Native_range] / [Introduced_range]: the list is non-empty; [Red_list],
    [Toxicity], [Organ_photos]: [Some]; [Links]: non-empty. [Life_form],
    [Fr_status], [Fr_protection], [Flowering_months], [Habitat], [Ecology]:
    always [false]: no fetched source fills them (they come from the regional
    layer, architecture §6). *)

val empty_fields : t -> Field.t list
(** The fields not {!filled}, in [Field.all] order. *)
