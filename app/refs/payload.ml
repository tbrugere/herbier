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
  | Wikipedia_uses
  | Tela_names
  | Tela_taxon
  | Tela_baseflor
  | Inpn_name
  | Inpn_status
  | Inpn_red_list
  | Inpn_protections
  | Plantuse_page

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
    Wikipedia_uses;
    Tela_names;
    Tela_taxon;
    Tela_baseflor;
    Inpn_name;
    Inpn_status;
    Inpn_red_list;
    Inpn_protections;
    Plantuse_page;
  ]

let source = function
  | Gbif_species | Gbif_vernacular_names | Gbif_distributions
  | Gbif_occurrence_count ->
      Source.Gbif
  | Plantnet_media -> Source.Plantnet
  | Wikidata_search | Wikidata_entity -> Source.Wikidata
  | Wikipedia_summary | Wikipedia_uses -> Source.Wikipedia
  | Tela_names | Tela_taxon | Tela_baseflor -> Source.Tela
  | Inpn_name | Inpn_status | Inpn_red_list | Inpn_protections -> Source.Taxref
  | Plantuse_page -> Source.Plantuse

let name = function
  | Gbif_species -> "species"
  | Gbif_vernacular_names -> "vernacular_names"
  | Gbif_distributions -> "distributions"
  | Gbif_occurrence_count -> "occurrence_count"
  | Plantnet_media -> "media"
  | Wikidata_search -> "search"
  | Wikidata_entity -> "entity"
  | Wikipedia_summary -> "summary"
  | Wikipedia_uses -> "uses"
  | Tela_names -> "names"
  | Tela_taxon -> "taxon"
  | Tela_baseflor -> "baseflor"
  | Inpn_name -> "name"
  | Inpn_status -> "status"
  | Inpn_red_list -> "red_list"
  | Inpn_protections -> "protections"
  | Plantuse_page -> "page"

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

let tela_taxon_fields =
  [
    "id";
    "nom_sci";
    "nom_retenu.id";
    "cd_nom";
    "presence.libelle";
    "statut_origine.libelle";
    "statut_introduction.libelle";
    "statut_culture.libelle";
  ]

let baseflor_fields =
  [
    "nom_sci";
    "floraison";
    "carac_ecolo";
    "chorologie";
    "type_bio.libelle";
    "type_bio.detail";
    "ve_lumiere.libelle";
    "ve_humidite_edaph.libelle";
    "ve_reaction_sol.libelle";
    "ve_nutriments_sol.libelle";
  ]

(* An INPN HAL page: [_embedded] holds one array of [key]. *)
let hal_page key element body =
  map_member "_embedded"
    (fun embedded -> map_member key (map_list element) (keep [key] embedded))
    (keep ["_embedded"; "page"] body)

let protection_article json =
  map_member "_embedded"
    (fun embedded ->
      map_member "scopeLocation"
        (keep ["locationId"; "name"; "level"; "overseas"])
        (keep ["scopeLocation"] embedded))
    (keep ["name"; "scope"; "type"; "category"; "_embedded"] json)

(* The headings, and the bodies of the sections Wikipedia.uses_line may
   read: a whole article is tens of kilobytes. *)
let uses_sections ~lang text =
  let _lead, sections = Wiki_text.sections text in
  String.concat "\n"
    (List.concat_map
       (fun ((s : Wiki_text.section), kept) ->
         let marks = String.make s.level '=' in
         let heading = marks ^ " " ^ s.title ^ " " ^ marks in
         match kept with true -> [heading; s.body] | false -> [heading])
       (Sources.Wikipedia.in_uses ~lang sections))

let extract_page page =
  let lang = Option.value ~default:"fr" (Decode.string "pagelanguage" page) in
  map_member "extract"
    (function
      | `String text -> `String (uses_sections ~lang text) | json -> json)
    (keep
       ["title"; "missing"; "invalid"; "pagelanguage"; "fullurl"; "extract"]
       page)

let prune part body =
  match part with
  | Gbif_species | Gbif_occurrence_count | Wikidata_search | Wikipedia_summary
  | Tela_names | Plantuse_page ->
      body
  | Wikipedia_uses ->
      map_member "query"
        (fun query ->
          map_member "pages" (map_list extract_page)
            (keep ["normalized"; "redirects"; "pages"] query))
        (keep ["query"; "error"] body)
  | Tela_taxon -> keep tela_taxon_fields body
  | Tela_baseflor -> keep baseflor_fields body
  | Inpn_name ->
      map_member "_links" (keep ["taxon"])
        (keep ["taxrefId"; "valid"; "binomialName"; "_links"] body)
  | Inpn_status ->
      hal_page "biogeographicStatuses"
        (keep ["biogeographicStatus"; "simplifiedBiogeographicStatus"])
        body
  | Inpn_red_list ->
      hal_page "redListEntries"
        (keep
           [
             "category";
             "categoryDescription";
             "trend";
             "evaluationYear";
             "_links";
           ])
        body
  | Inpn_protections -> hal_page "protectionArticles" protection_article body
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

let wikipedia ~summary ~uses =
  build [(Wikipedia_summary, summary); (Wikipedia_uses, uses)]

let plantuse ~page = build [(Plantuse_page, page)]

let tela ~names ~taxon ~baseflor =
  build [(Tela_names, names); (Tela_taxon, taxon); (Tela_baseflor, baseflor)]

let taxref ~name ~status ~red_list ~protections =
  build
    [
      (Inpn_name, name);
      (Inpn_status, status);
      (Inpn_red_list, red_list);
      (Inpn_protections, protections);
    ]

let get part = function
  | `Assoc members -> (
      match List.assoc_opt (name part) members with
      | None | Some `Null -> None
      | Some _ as v -> v)
  | _ -> None
