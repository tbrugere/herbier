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

type area = Origin.area = {code : string option; name : string}
(** See {!Origin.area}. *)

val equal_area : area -> area -> bool

type origin = {native : area list; introduced : area list}

type habitat = {phrase : string option; chips : string list}
(** At least one of the two is non-empty. *)

type protection =
  | Not_protected
      (** INPN answered, with no ["PROTECTION"] article outside overseas
          locations. *)
  | National  (** A ["PROTECTION"] article of scope ["NATIONAL"]. *)
  | Local of string list
      (** ["PROTECTION"] articles of scope ["REGIONAL"] then ["DEPARTMENTAL"]
          only: their location names, regions first then départements, each
          group in payload order, duplicates dropped. Articles whose location is
          overseas are ignored; one without a location adds no name (so
          [Local []] is possible). *)

type fr_red_list = {category : string; description : string option}
(** An entry of the national red list of metropolitan France (["LC"],
    ["Préoccupation mineure"]). *)

val equal_protection : protection -> protection -> bool
val pp_protection : Format.formatter -> protection -> unit
val equal_fr_red_list : fr_red_list -> fr_red_list -> bool
val pp_fr_red_list : Format.formatter -> fr_red_list -> unit

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
  life_form : string cited option;
      (** « Type »: Baseflor's principal biological type as written («
          Hémicryptophytes (>= 1m) bisannuels »), trimmed; [[Tela]]. *)
  origin : origin cited option;  (** [[Gbif]] (WCVP rows). *)
  red_list : string cited option;
      (** The global IUCN category as GBIF gives it (["LEAST_CONCERN"]);
          [[Gbif]]. *)
  flowering_months : int list cited option;
      (** 1..12, ascending, without duplicates, non-empty: Baseflor's
          [floraison] read by {!months}; [[Tela]]. *)
  habitat : habitat cited option;
      (** Baseflor's [carac_ecolo] (trimmed) as the phrase; its light, soil
          moisture, soil reaction and nutrient labels, each cut before its first
          [" ("], as the chips (blank ones and duplicates dropped); [[Tela]]. *)
  toxicity : string cited option;
      (** One sentence about toxicity, quoted as written, not a verdict: a
          negated one ("n'est pas toxique") is kept; [[Wikipedia]]. *)
  organ_photos : Sources.Gbif.Image.t list cited option;
      (** Per organ in [Reference.Organ.all] order (flower, leaf, fruit, habit),
          the first image of the page of that organ whose [url] is
          {!Organ_photos.downloadable}, so at most one per organ, each with
          [organ = Some _]; [[Plantnet]]; [None] when no organ has one. *)
  fr_status : string cited option;
      (** INPN's [biogeographicStatus] in metropolitan France as given
          (["PRESENT"]), the first entry; [[Taxref]]. *)
  fr_protection : protection cited option;
      (** [None] when the protections part is absent or does not decode;
          [[Taxref]]. *)
  fr_red_list : fr_red_list cited option;
      (** The first entry of the national red list; [[Taxref]]. *)
  links : link list;  (** In the order of {!link_order}; may be empty. *)
  problems : problem list;
      (** In [Payload.all] order of the failing parts. [Gbif_occurrence_count],
          [Wikidata_search], [Tela_names], [Tela_taxon] and [Inpn_name] are
          decoded only for this list: no field reads them. *)
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
      neither; payload order; duplicates dropped (the first kept): two rows are
      duplicates when both have a [code] and the codes are equal, or when either
      has none and the [name]s are equal;
    - red list: the first IUCN Red List row without a [country] with a
      [threat_status];
    - toxicity: from a [Standard] summary only, the first sentence of [extract]
      (cut after ['.'], ['!'] or ['?'] followed by a space or a newline, except
      a ['.'] after a lone capital such as the author initial in ["L. "], and at
      every newline) whose lowercase (ASCII and Latin-1 capitals folded)
      contains ["toxique"], ["toxic"], ["vénéneu"] or ["poison"], trimmed; else
      the [description] when it matches;
    - life form, flowering months, habitat: from the Tela row's [baseflor] part,
      as their fields say; the French status, protection and red list: from the
      Taxref row's [status], [protections] and [red_list] parts;
    - organ photos: per organ, the first Pl@ntNet image of that organ whose URL
      is {!Organ_photos.downloadable} ({!Organ_photos.wanted});
    - links: per source of {!link_order}, the [url] of the first live plant ref
      of that source whose [url] is https, has no whitespace or control
      character, and points at that source ({!Herbier_domain.Link.classify}
      gives that source's constructor, [Inpn] for [Taxref]; for EPPO, Wikidata
      and IPNI, which it does not know, the host is [gd.eppo.int],
      [www.wikidata.org] or [m.wikidata.org], [www.ipni.org] or [ipni.org]);
      else a URL derived from the ids (GBIF key, the [Standard] summary's https
      page URL that classifies as Wikipedia, the entity's POWO, TaxRef, Tela,
      iNaturalist and EPPO ids), else none. *)

val months : string -> int list option
(** Baseflor's [floraison] ("5-9", "6", "4-6,9"): pieces split on [','], each
    trimmed is ["a"] or ["a-b"] with [a] and [b] plain digits in 1..12; [a > b]
    wraps through December ("11-2" → 11, 12, 1, 2). Ascending, without
    duplicates. [None] when a piece does not parse or nothing is left (the field
    is then [None], with no problem: the part decoded). *)

val organ_photos_wanted : t -> (Reference.Organ.t * Sources.Gbif.Image.t) list
(** [organ_photos] paired with their organ, [[]] when [None]: the [wanted] of
    {!Organ_photos.plan} and {!Organ_photos.shown}, for the thumbnail sync and
    for 4f alike. [plant_refs] never change it, so a projection made with
    [plant_refs:[]] gives the same list. *)

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
    [Native_range] / [Introduced_range]: the list is non-empty; [Life_form],
    [Red_list], [Flowering_months], [Toxicity], [Organ_photos]: [Some];
    [Habitat]: the habitat has a [phrase]; [Ecology]: the habitat has non-empty
    [chips]; [Links]: non-empty; [Fr_status]: [fr_status <> None];
    [Fr_protection]: [fr_protection <> None]. *)

val empty_fields : t -> Field.t list
(** The fields not {!filled}, in [Field.all] order. *)
