module Reference = Herbier_domain.Reference
module Source = Reference.Source
module Gbif = Sources.Gbif
module Wikidata = Sources.Wikidata
module Wikipedia = Sources.Wikipedia
module Lang = Vernacular.Lang

type 'a cited = 'a Cited.t = {value : 'a; sources : Source.t list}
type vernacular = Vernacular.t = {lang : Lang.t; names : string list}
type area = Origin.area = {code : string option; name : string}

let equal_area = Origin.equal_area

type origin = Origin.t = {native : area list; introduced : area list}
type habitat = {phrase : string option; chips : string list}
type link = Links.t = {source : Source.t; url : string}
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

let link_order = Links.link_order
let cited = Cited.v

(* Live rows of fetched sources, the first of each source. *)
let used_rows references =
  List.fold_left
    (fun acc (r : Reference.t) ->
      match
        ( r.deleted_at,
          Payload.parts r.source,
          List.exists
            (fun (u : Reference.t) -> Source.equal u.source r.source)
            acc )
      with
      | None, _ :: _, false -> r :: acc
      | Some _, _, _ | None, [], _ | None, _ :: _, true -> acc)
    [] references
  |> List.rev

(* A payload that is not an object holds none of its source's parts: each
   is reported, not silently empty. *)
let decode rows part decoder =
  match
    List.find_opt
      (fun (r : Reference.t) -> Source.equal r.source (Payload.source part))
      rows
  with
  | None -> None
  | Some ({payload = `Assoc _; _} as r) ->
      Option.map decoder (Payload.get part r.payload)
  | Some _ -> Some (Decode.unexpected "" "object")

let ok = function Some (Ok v) -> Some v | Some (Error _) | None -> None

let problem part = function
  | Some (Error error) -> Some {part; error}
  | Some (Ok _) | None -> None

let organ_photos (page : Gbif.Image.t Gbif.page) =
  match Organ_photos.wanted page.results with
  | [] -> None
  | photos -> Some (cited [Source.Plantnet] (List.map snd photos))

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
      Vernacular.vernacular
        (Option.fold ~none:[] ~some:Vernacular.gbif_votes (ok vernacular_names)
        @ Option.fold ~none:[] ~some:Vernacular.wikidata_votes entity_value);
    life_form = None;
    origin = Option.bind distributions_value Origin.origin;
    red_list = Option.bind distributions_value Origin.red_list;
    flowering_months = None;
    habitat = None;
    toxicity = Option.bind summary_value Toxicity.toxicity;
    organ_photos = Option.bind (ok media) organ_photos;
    links =
      Links.links ~plant_refs ~taxon ~entity:entity_value ~summary:summary_value;
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
