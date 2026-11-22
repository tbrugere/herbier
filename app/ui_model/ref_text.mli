(** Texts of 4f's reference block. Pure. *)

val source_name : Herbier_domain.Reference.Source.t -> string
(** "GBIF", "Wikidata", "Wikipédia", "POWO", "IPNI", "INPN" (taxref), "Tela
    Botanica", "EPPO", "iNaturalist", "Pl@ntNet", "Pl@ntUse". *)

val names_line : Herbier_refs.Projection.vernacular -> string
(** The names joined with [", "] (the language code is rendered apart, bold). *)

val names_source_line :
  family:string option -> Herbier_domain.Reference.Source.t list -> string
(** The « Noms » sub-line: ["Plantaginaceae · GBIF, Wikidata"]; without a
    family, the sources alone; [""] with neither. *)

val sources_line : Herbier_domain.Reference.Source.t list -> string
(** [source_name]s joined with [", "]; [""] for []. *)

val other_languages : string
(** ["Autres langues"]: the label of 4f « Noms »'s disclosure. *)

val area_name : Herbier_refs.Projection.area -> string
(** [Wgsrpd_fr.name code] when [code = Some code] and it is known; else the
    area's [name] (GBIF's English). *)

val origin_names : Herbier_refs.Projection.area list -> string list
(** [area_name] of each, duplicates dropped (equal after
    [Herbier_domain.Fold.fold]; the first spelling kept), sorted by [Fold.fold]
    (unique after the dedup; French order: accents and case ignored, « Îles
    Canaries » between « Hongrie » and « Irlande »). *)

val in_source_order :
  Herbier_domain.Reference.Source.t list ->
  Herbier_domain.Reference.Source.t list
(** The given sources in [Reference.Source.all] order, without repeats. *)

val origin_line : string list -> string option
(** [None] for []; up to 6 names: all, joined with [", "]; more: the first 5,
    then [" et <n> autres"] ([n] = the rest), e.g.
    ["Allemagne, Belgique, Corse, France, Grande-Bretagne et 7 autres"]. *)

val red_list : string -> string option
(** GBIF's IUCN category → the chip: ["LEAST_CONCERN"] →
    ["LC · préoccupation mineure"], ["NEAR_THREATENED"] →
    ["NT · quasi menacée"], ["VULNERABLE"] → ["VU · vulnérable"], ["ENDANGERED"]
    → ["EN · en danger"], ["CRITICALLY_ENDANGERED"] →
    ["CR · en danger critique"], ["EXTINCT_IN_THE_WILD"] →
    ["EW · éteinte à l'état sauvage"], ["EXTINCT"] → ["EX · éteinte"],
    ["DATA_DEFICIENT"] → ["DD · données insuffisantes"]; ["NOT_EVALUATED"] and
    ["NOT_APPLICABLE"] → [None] (no data: the row disappears); any other string
    → [Some] of it as given. *)

val fr_status : string -> string option
(** INPN's status in metropolitan France → the « En France » chip: ["PRESENT"] →
    ["Indigène"], ["ENDEMIC"] → ["Endémique"], ["SUBENDEMIC"] →
    ["Subendémique"], ["CRYPTOGENIC"] → ["Cryptogène"], ["INTRODUCED"] →
    ["Introduite"], ["INVASIVE"] → ["Introduite envahissante"],
    ["NOT_NATURALIZED"] → ["Introduite non établie"], ["OCCASIONAL"] →
    ["Occasionnelle"], ["DOUBTFUL"] → ["Présence douteuse"], ["ABSENT"] →
    ["Absente"], ["DISAPPEARED"] → ["Disparue"], ["EXTINCT"] → ["Éteinte"]; any
    other string → [None] (no chip). *)

val fr_protection : Herbier_refs.Projection.protection -> string
(** [Not_protected] → ["Non protégée"], [National] → ["Protégée en France"],
    [Local [p]] → ["Protégée (<p>)"], any other [Local] →
    ["Protégée localement"]. *)

val fr_places : Herbier_refs.Projection.protection -> string option
(** For [Local names] with 2 names or more: ["Protection : "] then
    {!origin_line} of the names; [None] otherwise. *)

val fr_red_list : Herbier_refs.Projection.fr_red_list -> string option
(** ["Liste rouge : <code> · <label>"] with the labels of {!red_list} for
    ["LC"], ["NT"], ["VU"], ["EN"], ["CR"], ["DD"], ["EW"], ["EX"], and ["RE"] →
    ["disparue en France"]; ["NA"] and ["NE"] → [None] (not evaluated: no chip);
    another category → ["Liste rouge : <category>"], followed by [" · "] and the
    description in lowercase when there is one. *)

val month_letter : int -> string
(** 1..12 → ["J"], ["F"], ["M"], ["A"], ["M"], ["J"], ["J"], ["A"], ["S"],
    ["O"], ["N"], ["D"]; outside → [""]. *)

val months_text : int list -> string
(** Runs of consecutive months (December followed by January counts, unless all
    twelve are there), each ["<m>"] or ["<a> – <b>"] with French month names in
    lowercase (« juin – août »), runs ordered by their first month ascending (a
    run wrapping December → January starts at its first month, e.g. novembre)
    and joined with [", "]; all twelve → ["toute l'année"]; [] → [""]. Values
    outside 1..12 and duplicates are ignored. Examples: [[6;7;8]] →
    ["juin – août"]; [[12;1;2]] → ["décembre – février"]; [[3;4;9]] →
    ["mars – avril, septembre"]; [[5]] → ["mai"]. *)

val organ_label : Herbier_domain.Reference.Organ.t -> string
(** ["fleur"], ["feuille"], ["fruit"], ["port"]. *)

val credits : Herbier_domain.Reference.Image.t list -> string
(** ["Photos : "] then ["<attribution> (<licence>)"] per image, in order,
    duplicates (same attribution and licence) dropped, joined with [", "]; [""]
    for []. *)

val link_label : Herbier_domain.Reference.Source.t -> string
(** [source_name ^ " ↗"]. *)

val uses_label : string
(** ["Utilisations"]: the label of 4f's uses row. *)

val plantuse_credit : string
(** ["Pl@ntUse · CC BY-SA"]. *)

val wikipedia_uses_credit : lang:string -> section:string -> string
(** ["Wikipédia · « <section> » · CC BY-SA · extrait automatique"]; for a [lang]
    other than ["fr"], ["Wikipédia (<lang>) · « … » · …"]. « extrait automatique
    » marks the heuristic: the paragraph is picked by its section title. *)
