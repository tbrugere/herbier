module Source = Herbier_domain.Reference.Source

type part =
  | Gbif_species
  | Gbif_vernacular_names
  | Gbif_distributions
  | Gbif_occurrence_count
  | Plantnet_media
  | Wikidata_search
  | Wikidata_entity
  | Wikipedia_summary

let all =
  [
    Gbif_species;
    Gbif_vernacular_names;
    Gbif_distributions;
    Gbif_occurrence_count;
    Plantnet_media;
    Wikidata_search;
    Wikidata_entity;
    Wikipedia_summary;
  ]

let source = function
  | Gbif_species | Gbif_vernacular_names | Gbif_distributions
  | Gbif_occurrence_count ->
      Source.Gbif
  | Plantnet_media -> Source.Plantnet
  | Wikidata_search | Wikidata_entity -> Source.Wikidata
  | Wikipedia_summary -> Source.Wikipedia

let name = function
  | Gbif_species -> "species"
  | Gbif_vernacular_names -> "vernacular_names"
  | Gbif_distributions -> "distributions"
  | Gbif_occurrence_count -> "occurrence_count"
  | Plantnet_media -> "media"
  | Wikidata_search -> "search"
  | Wikidata_entity -> "entity"
  | Wikipedia_summary -> "summary"

let parts s = List.filter (fun p -> source p = s) all

(* Every helper below matches on the shape and keeps anything unexpected as
   given, so the decoders see the same error on a pruned body. *)

let keep keys = function
  | `Assoc members ->
      `Assoc (List.filter (fun (k, _) -> List.mem k keys) members)
  | json -> json

let map_member key f = function
  | `Assoc members ->
      `Assoc
        (List.map
           (fun (k, v) ->
             match k = key with true -> (k, f v) | false -> (k, v))
           members)
  | json -> json

let map_list f = function
  | `List items -> `List (List.map f items)
  | json -> json

let map_values f = function
  | `Assoc members -> `Assoc (List.map (fun (k, v) -> (k, f v)) members)
  | json -> json

let page fields body =
  map_member "results"
    (map_list (keep fields))
    (keep ["results"; "endOfRecords"; "count"] body)

let media_fields =
  [
    "type"; "identifier"; "title"; "license"; "rightsHolder"; "creator"; "source";
  ]

let occurrence json =
  map_member "media"
    (map_list (keep media_fields))
    (keep ["key"; "references"; "media"] json)

let properties =
  ["P846"; "P5037"; "P961"; "P3186"; "P3105"; "P3031"; "P3151"; "P1843"]

let claims json =
  map_values (map_list (keep ["rank"; "mainsnak"])) (keep properties json)

let entity json =
  keep ["id"; "missing"; "claims"; "sitelinks"] json
  |> map_member "claims" claims
  |> map_member "sitelinks" (keep ["frwiki"; "enwiki"; "dewiki"; "itwiki"])

let prune part body =
  match part with
  | Gbif_species | Gbif_occurrence_count | Wikidata_search | Wikipedia_summary
    ->
      body
  | Gbif_vernacular_names ->
      page ["vernacularName"; "language"; "source"; "country"] body
  | Gbif_distributions ->
      page
        [
          "locationId";
          "locality";
          "country";
          "status";
          "establishmentMeans";
          "threatStatus";
          "source";
        ]
        body
  | Plantnet_media ->
      map_member "results" (map_list occurrence)
        (keep ["results"; "endOfRecords"; "count"] body)
  | Wikidata_entity ->
      map_member "entities" (map_values entity)
        (keep ["entities"; "error"] body)

let build members =
  `Assoc
    (List.filter_map
       (fun (part, body) ->
         Option.map (fun b -> (name part, prune part b)) body)
       members)

let gbif ~species ~vernacular_names ~distributions ~occurrence_count =
  build
    [
      (Gbif_species, species);
      (Gbif_vernacular_names, vernacular_names);
      (Gbif_distributions, distributions);
      (Gbif_occurrence_count, occurrence_count);
    ]

let plantnet ~media = build [(Plantnet_media, media)]

let wikidata ~search ~entity =
  build [(Wikidata_search, search); (Wikidata_entity, entity)]

let wikipedia ~summary = build [(Wikipedia_summary, summary)]

let get part = function
  | `Assoc members -> (
      match List.assoc_opt (name part) members with
      | None | Some `Null -> None
      | Some _ as v -> v)
  | _ -> None
