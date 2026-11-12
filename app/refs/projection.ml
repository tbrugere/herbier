module Reference = Herbier_domain.Reference
module Source = Reference.Source
module Link = Herbier_domain.Link
module Gbif = Sources.Gbif
module Wikidata = Sources.Wikidata
module Wikipedia = Sources.Wikipedia

module Lang = struct
  type t = Fr | En | De | It

  let all = [Fr; En; De; It]
  let to_string = function Fr -> "fr" | En -> "en" | De -> "de" | It -> "it"
end

type 'a cited = {value : 'a; sources : Source.t list}
type vernacular = {lang : Lang.t; names : string list}
type origin = {native : string list; introduced : string list}
type habitat = {phrase : string option; chips : string list}
type link = {source : Source.t; url : string}
type problem = {part : Payload.part; error : Decode.error}

type t = {
  fetched_at : Ptime.t option;
  taxon : Gbif.Taxon.t cited option;
  vernacular : vernacular list cited option;
  life_form : string cited option;
  origin : origin cited option;
  red_list : string cited option;
  flowering_months : int list cited option;
  habitat : habitat cited option;
  toxicity : string cited option;
  organ_photos : Gbif.Image.t list cited option;
  links : link list;
  problems : problem list;
}

let link_order =
  [
    Source.Gbif;
    Plantnet;
    Wikipedia;
    Powo;
    Taxref;
    Tela;
    Inat;
    Eppo;
    Wikidata;
    Ipni;
  ]

let cited sources value = {value; sources}

(* Live rows of fetched sources, the first of each source. *)
let used_rows references =
  List.fold_left
    (fun acc (r : Reference.t) ->
      match
        ( r.deleted_at,
          Payload.parts r.source,
          List.exists (fun (u : Reference.t) -> u.source = r.source) acc )
      with
      | None, _ :: _, false -> r :: acc
      | Some _, _, _ | None, [], _ | None, _ :: _, true -> acc)
    [] references
  |> List.rev

(* A payload that is not an object holds none of its source's parts: each
   is reported, not silently empty. *)
let decode rows part decoder =
  match
    List.find_opt (fun (r : Reference.t) -> r.source = Payload.source part) rows
  with
  | None -> None
  | Some ({payload = `Assoc _; _} as r) ->
      Option.map decoder (Payload.get part r.payload)
  | Some _ -> Some (Decode.unexpected "" "object")

let ok = function Some (Ok v) -> Some v | Some (Error _) | None -> None

let problem part = function
  | Some (Error error) -> Some {part; error}
  | Some (Ok _) | None -> None

let dedup_first key items =
  List.rev
    (List.fold_left
       (fun acc x ->
         match List.exists (fun y -> key y = key x) acc with
         | true -> acc
         | false -> x :: acc)
       [] items)

(* {1 Vernacular names} *)

let gbif_lang = function
  | "fra" -> Some Lang.Fr
  | "eng" -> Some Lang.En
  | "deu" -> Some Lang.De
  | "ita" -> Some Lang.It
  | _ -> None

let wikidata_lang = function
  | "fr" -> Some Lang.Fr
  | "en" -> Some Lang.En
  | "de" -> Some Lang.De
  | "it" -> Some Lang.It
  | _ -> None

type vote = {vote_lang : Lang.t; name : string; from : Source.t}

let gbif_votes (page : Gbif.Vernacular.t Gbif.page) =
  List.concat_map
    (fun (v : Gbif.Vernacular.t) ->
      match Option.bind v.language gbif_lang with
      | None -> []
      | Some vote_lang ->
          List.filter_map
            (fun piece ->
              Option.map
                (fun name -> {vote_lang; name; from = Source.Gbif})
                (Decode.non_blank (String.trim piece)))
            (String.split_on_char ',' v.name))
    page.results

let wikidata_votes (entity : Wikidata.Entity.t) =
  List.filter_map
    (fun (n : Wikidata.Entity.name) ->
      match wikidata_lang n.lang with
      | None -> None
      | Some vote_lang ->
          Option.map
            (fun name -> {vote_lang; name; from = Source.Wikidata})
            (Decode.non_blank (String.trim n.text)))
    entity.common_names

type group = {spelling : string; count : int; froms : Source.t list}

(* Groups are built in reverse order of their first vote, then reversed, so
   a stable sort on the count breaks ties by first position. *)
let groups votes =
  List.fold_left
    (fun acc v ->
      let key = String.lowercase_ascii v.name in
      match List.mem_assoc key acc with
      | true ->
          List.map
            (fun (k, g) ->
              match k = key with
              | true ->
                  (k, {g with count = g.count + 1; froms = v.from :: g.froms})
              | false -> (k, g))
            acc
      | false -> (key, {spelling = v.name; count = 1; froms = [v.from]}) :: acc)
    [] votes
  |> List.rev_map snd
  |> List.stable_sort (fun a b -> compare b.count a.count)
  |> List.take 3

let in_source_order sources =
  List.filter (fun s -> List.mem s sources) Source.all

let vernacular votes =
  let kept =
    List.filter_map
      (fun lang ->
        match groups (List.filter (fun v -> v.vote_lang = lang) votes) with
        | [] -> None
        | gs -> Some (lang, gs))
      Lang.all
  in
  match kept with
  | [] -> None
  | _ ->
      Some
        (cited
           (in_source_order
              (List.concat_map
                 (fun (_, gs) -> List.concat_map (fun g -> g.froms) gs)
                 kept))
           (List.map
              (fun (lang, gs) ->
                {lang; names = List.map (fun g -> g.spelling) gs})
              kept))

(* {1 Distributions} *)

(* GBIF's distribution statuses that say the taxon occurs there; ABSENT,
   EXCLUDED and DOUBTFUL do not. *)
let present = function
  | None | Some ("PRESENT" | "COMMON" | "RARE" | "IRREGULAR") -> true
  | Some _ -> false

type means = Native | Introduced

(* WCVP leaves native rows without establishmentMeans. UNCERTAIN, or a value
   GBIF may add, is neither. *)
let means = function
  | None | Some "NATIVE" -> Some Native
  | Some ("INTRODUCED" | "NATURALISED" | "INVASIVE" | "MANAGED") ->
      Some Introduced
  | Some _ -> None

let origin (page : Gbif.Distribution.t Gbif.page) =
  let rows =
    List.filter_map
      (fun (d : Gbif.Distribution.t) ->
        match
          (d.source, d.locality, present d.status, means d.establishment_means)
        with
        | ( Some "The World Checklist of Vascular Plants (WCVP)",
            Some locality,
            true,
            Some m ) ->
            Some (locality, m)
        | _ -> None)
      page.results
  in
  let native, introduced =
    List.partition
      (fun (_, m) -> match m with Native -> true | Introduced -> false)
      rows
  in
  match
    ( dedup_first Fun.id (List.map fst native),
      dedup_first Fun.id (List.map fst introduced) )
  with
  | [], [] -> None
  | native, introduced -> Some (cited [Source.Gbif] {native; introduced})

let red_list (page : Gbif.Distribution.t Gbif.page) =
  List.find_map
    (fun (d : Gbif.Distribution.t) ->
      match (d.source, d.country, d.threat_status) with
      | Some "The IUCN Red List of Threatened Species", None, Some status ->
          Some (cited [Source.Gbif] status)
      | _ -> None)
    page.results

(* {1 Toxicity} *)

let contains ~sub s =
  let n = String.length sub and m = String.length s in
  let rec at i = i + n <= m && (String.sub s i n = sub || at (i + 1)) in
  at 0

(* String.lowercase_ascii leaves accented capitals alone: the Latin-1 ones
   (UTF-8 C3 80 to C3 9E, but the sign at C3 97) are folded too, so
   "VÉNÉNEUX" matches. *)
let lowercase s =
  String.mapi
    (fun i c ->
      match
        i > 0 && s.[i - 1] = '\xc3' && c >= '\x80' && c <= '\x9e' && c <> '\x97'
      with
      | true -> Char.chr (Char.code c + 0x20)
      | false -> Char.lowercase_ascii c)
    s

let toxic s =
  let s = lowercase s in
  List.exists
    (fun sub -> contains ~sub s)
    ["toxique"; "toxic"; "vénéneu"; "poison"]

let blank c = c = ' ' || c = '\n'

(* A dot after a lone capital is an author's initial ("Digitalis purpurea
   L. est"), not the end of a sentence. *)
let initial s i =
  i >= 1 && s.[i - 1] >= 'A' && s.[i - 1] <= 'Z' && (i = 1 || blank s.[i - 2])

let sentences s =
  let n = String.length s in
  let rec skip i =
    match i < n && blank s.[i] with true -> skip (i + 1) | false -> i
  in
  let rec go start i acc =
    match i >= n with
    | true -> List.rev (String.sub s start (n - start) :: acc)
    | false -> (
        let cut =
          match s.[i] with
          | '\n' -> Some i
          | '.' | '!' | '?' -> (
              match
                i + 1 < n && blank s.[i + 1] && not (s.[i] = '.' && initial s i)
              with
              | true -> Some (i + 1)
              | false -> None)
          | _ -> None
        in
        match cut with
        | Some stop ->
            let next = skip stop in
            go next next (String.sub s start (stop - start) :: acc)
        | None -> go start (i + 1) acc)
  in
  go 0 0 []

let toxicity (summary : Wikipedia.t) =
  match summary.kind with
  | Disambiguation | Other _ -> None
  | Standard -> (
      let from_extract =
        Option.bind summary.extract (fun e -> List.find_opt toxic (sentences e))
      in
      match from_extract with
      | Some s -> Some (cited [Source.Wikipedia] (String.trim s))
      | None -> (
          match summary.description with
          | Some d when toxic d ->
              Some (cited [Source.Wikipedia] (String.trim d))
          | Some _ | None -> None))

let organ_photos (page : Gbif.Image.t Gbif.page) =
  match Organ_photos.wanted page.results with
  | [] -> None
  | photos -> Some (cited [Source.Plantnet] (List.map snd photos))

(* {1 Links}

   The URL builders below have their parser in Herbier_domain.Link; the
   link_classification test of test_projection checks that every derived
   link classifies back to its source. *)

let all_chars f s = s <> "" && String.for_all f s

let powo_url powo =
  let prefix = "urn:lsid:ipni.org:names:" in
  let p = String.length prefix in
  match String.starts_with ~prefix powo with
  | false -> None
  | true -> (
      match
        all_chars
          (function '0' .. '9' | '-' -> true | _ -> false)
          (String.sub powo p (String.length powo - p))
      with
      | true -> Some ("https://powo.science.kew.org/taxon/" ^ powo)
      | false -> None)

let eppo_url eppo =
  match
    all_chars (function 'A' .. 'Z' | '0' .. '9' -> true | _ -> false) eppo
  with
  | true -> Some ("https://gd.eppo.int/taxon/" ^ eppo)
  | false -> None

(* Link.classify reads ids as positive ints, so a derived link is built
   only from one. *)
let positive prefix = function
  | Some n when n > 0 -> Some (prefix ^ string_of_int n)
  | Some _ | None -> None

let wikipedia_url (summary : Wikipedia.t) =
  match (summary.kind, summary.page_url) with
  | Standard, Some url when String.starts_with ~prefix:"https://" url -> (
      match Link.classify url with
      | Wikipedia _ -> Some url
      | Gbif _ | Plantnet _ | Plantnet_observation _ | Plantuse _ | Inpn _
      | Tela _ | Powo _ | Inat _ | Text _ ->
          None)
  | (Standard | Disambiguation | Other _), _ -> None

let derived ~taxon ~entity ~summary source =
  let from_entity f = Option.bind entity f in
  match (source : Source.t) with
  | Gbif -> Option.map (fun (t : Gbif.Taxon.t) -> Gbif.species_url t.key) taxon
  | Wikipedia -> Option.bind summary wikipedia_url
  | Powo ->
      from_entity (fun (e : Wikidata.Entity.t) -> Option.bind e.powo powo_url)
  | Taxref ->
      from_entity (fun (e : Wikidata.Entity.t) ->
          positive "https://inpn.mnhn.fr/espece/cd_nom/" e.taxref)
  | Tela ->
      from_entity (fun (e : Wikidata.Entity.t) ->
          positive "https://www.tela-botanica.org/bdtfx-nn-" e.tela)
  | Inat ->
      from_entity (fun (e : Wikidata.Entity.t) ->
          positive "https://www.inaturalist.org/taxa/" e.inat)
  | Eppo ->
      from_entity (fun (e : Wikidata.Entity.t) -> Option.bind e.eppo eppo_url)
  | Plantnet | Wikidata | Ipni -> None

let classified_source : Link.t -> Source.t option = function
  | Gbif _ -> Some Gbif
  | Plantnet _ | Plantnet_observation _ | Plantuse _ -> Some Plantnet
  | Wikipedia _ -> Some Wikipedia
  | Inpn _ -> Some Taxref
  | Tela _ -> Some Tela
  | Powo _ -> Some Powo
  | Inat _ -> Some Inat
  | Text _ -> None

(* Hosts of the sources Link.classify has no constructor for. *)
let prefixes : Source.t -> string list = function
  | Eppo -> ["https://gd.eppo.int/"]
  | Wikidata -> ["https://www.wikidata.org/"; "https://m.wikidata.org/"]
  | Ipni -> ["https://www.ipni.org/"; "https://ipni.org/"]
  | Gbif | Plantnet | Wikipedia | Powo | Taxref | Tela | Inat -> []

let stored_url_ok source url =
  String.starts_with ~prefix:"https://" url
  && String.for_all (fun c -> c > ' ' && c <> '\x7f') url
  &&
  match classified_source (Link.classify url) with
  | Some s -> s = source
  | None ->
      List.exists
        (fun prefix -> String.starts_with ~prefix url)
        (prefixes source)

let links ~plant_refs ~taxon ~entity ~summary =
  List.filter_map
    (fun source ->
      let stored =
        List.find_opt
          (fun (r : Reference.Plant_ref.t) ->
            r.source = source
            && Option.is_none r.deleted_at
            && stored_url_ok source r.url)
          plant_refs
      in
      match stored with
      | Some r -> Some {source; url = r.url}
      | None ->
          Option.map
            (fun url -> {source; url})
            (derived ~taxon ~entity ~summary source))
    link_order

(* {1 Projection} *)

let project ~references ~plant_refs =
  let rows = used_rows references in
  let decode part decoder = decode rows part decoder in
  let species = decode Gbif_species Gbif.species_of_json in
  let vernacular_names =
    decode Gbif_vernacular_names Gbif.vernacular_names_of_json
  in
  let distributions = decode Gbif_distributions Gbif.distributions_of_json in
  let occurrence_count =
    decode Gbif_occurrence_count Gbif.occurrence_count_of_json
  in
  let media = decode Plantnet_media Gbif.plantnet_media_of_json in
  let search = decode Wikidata_search Wikidata.search_of_json in
  let entity = decode Wikidata_entity Wikidata.entity_of_json in
  let summary = decode Wikipedia_summary Wikipedia.summary_of_json in
  let taxon = ok species in
  let entity_value = Option.join (ok entity) in
  let summary_value = ok summary in
  let distributions_value = ok distributions in
  {
    fetched_at =
      List.fold_left
        (fun acc (r : Reference.t) ->
          match r.status with
          | Reference.Status.Failed -> acc
          | Complete | Partial | Missing -> (
              match acc with
              | Some t when Ptime.is_earlier t ~than:r.fetched_at -> acc
              | Some _ | None -> Some r.fetched_at))
        None rows;
    taxon = Option.map (cited [Source.Gbif]) taxon;
    vernacular =
      vernacular
        (Option.fold ~none:[] ~some:gbif_votes (ok vernacular_names)
        @ Option.fold ~none:[] ~some:wikidata_votes entity_value);
    life_form = None;
    origin = Option.bind distributions_value origin;
    red_list = Option.bind distributions_value red_list;
    flowering_months = None;
    habitat = None;
    toxicity = Option.bind summary_value toxicity;
    organ_photos = Option.bind (ok media) organ_photos;
    links = links ~plant_refs ~taxon ~entity:entity_value ~summary:summary_value;
    problems =
      List.filter_map Fun.id
        [
          problem Gbif_species species;
          problem Gbif_vernacular_names vernacular_names;
          problem Gbif_distributions distributions;
          problem Gbif_occurrence_count occurrence_count;
          problem Plantnet_media media;
          problem Wikidata_search search;
          problem Wikidata_entity entity;
          problem Wikipedia_summary summary;
        ];
  }

module Field = struct
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

  let all =
    [
      Vernacular;
      Family;
      Life_form;
      Native_range;
      Introduced_range;
      Fr_status;
      Fr_protection;
      Red_list;
      Flowering_months;
      Habitat;
      Ecology;
      Toxicity;
      Organ_photos;
      Links;
    ]

  let to_string = function
    | Vernacular -> "vernacular"
    | Family -> "family"
    | Life_form -> "life_form"
    | Native_range -> "native_range"
    | Introduced_range -> "introduced_range"
    | Fr_status -> "fr_status"
    | Fr_protection -> "fr_protection"
    | Red_list -> "red_list"
    | Flowering_months -> "flowering_months"
    | Habitat -> "habitat"
    | Ecology -> "ecology"
    | Toxicity -> "toxicity"
    | Organ_photos -> "organ_photos"
    | Links -> "links"
end

let filled t = function
  | Field.Vernacular -> Option.is_some t.vernacular
  | Family ->
      Option.is_some
        (Option.bind t.taxon (fun (c : Gbif.Taxon.t cited) -> c.value.family))
  | Native_range ->
      Option.fold ~none:false ~some:(fun c -> c.value.native <> []) t.origin
  | Introduced_range ->
      Option.fold ~none:false ~some:(fun c -> c.value.introduced <> []) t.origin
  | Life_form -> Option.is_some t.life_form
  | Red_list -> Option.is_some t.red_list
  | Flowering_months -> Option.is_some t.flowering_months
  | Habitat ->
      Option.fold ~none:false
        ~some:(fun c -> Option.is_some c.value.phrase)
        t.habitat
  | Ecology ->
      Option.fold ~none:false ~some:(fun c -> c.value.chips <> []) t.habitat
  | Toxicity -> Option.is_some t.toxicity
  | Organ_photos -> Option.is_some t.organ_photos
  | Links -> t.links <> []
  | Fr_status | Fr_protection -> false

let empty_fields t = List.filter (fun f -> not (filled t f)) Field.all

let organ_photos_wanted t =
  Option.fold ~none:[]
    ~some:(fun (c : _ cited) -> Organ_photos.wanted c.value)
    t.organ_photos
