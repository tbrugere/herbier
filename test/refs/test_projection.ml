module Value = Herbier_test_support.Value
module Ids = Herbier_domain.Ids
module Reference = Herbier_domain.Reference
module Source = Herbier_domain.Reference.Source
module Organ = Herbier_domain.Reference.Organ
module Link = Herbier_domain.Link
module Decode = Herbier_refs.Decode
module Payload = Herbier_refs.Payload
module Projection = Herbier_refs.Projection
module Source_url = Herbier_refs.Source_url
module Gbif = Herbier_refs.Sources.Gbif
module Testable = Herbier_test_support.Testable

(* ---------- fixtures, ids and times ---------- *)

let plant =
  match Ids.Plant_id.of_string "00000000-0000-4000-8000-000000000001" with
  | Some x -> x
  | None -> invalid_arg "plant id"

let time = Value.time
let t_gbif = time "2026-11-01T10:00:00Z"
let t_other = time "2026-11-01T11:00:00Z"

let reference_row ?(status = Reference.Status.Complete) ?deleted_at ~source
    ~fetched_at payload : Reference.t =
  {
    id = Reference.id_of_key ~plant ~source;
    plant_id = plant;
    source;
    fetched_at;
    payload;
    status;
    created_at = fetched_at;
    updated_at = fetched_at;
    deleted_at;
  }

let plant_ref ?deleted_at ~source ~external_id ~url at : Reference.Plant_ref.t =
  {
    id = Reference.Plant_ref.id_of_key ~plant ~source;
    plant_id = plant;
    source;
    external_id;
    url;
    created_at = at;
    updated_at = at;
    deleted_at;
  }

type species = {
  species_body : Yojson.Safe.t;
  vernacular_names : Yojson.Safe.t;
  distributions : Yojson.Safe.t;
  occurrence_count : Yojson.Safe.t;
  plantnet_media : Yojson.Safe.t;
  search_p846 : Yojson.Safe.t;
  entity : Yojson.Safe.t;
  summary_fr : Yojson.Safe.t;
  uses : Yojson.Safe.t;  (** The wikipedia row's stored [uses] member *)
  plantuse_page : Yojson.Safe.t;  (** The plantuse row's [page] member *)
}

let digitalis =
  {
    species_body = Check.json "gbif_species_5414995.json";
    vernacular_names = Check.json "gbif_vernacular_names_5414995.json";
    distributions = Check.json "gbif_distributions_5414995.json";
    occurrence_count = Check.json "gbif_occurrence_count_5414995.json";
    plantnet_media = Check.json "gbif_plantnet_media_5414995.json";
    search_p846 = Check.json "wikidata_search_p846_5414995.json";
    entity = Check.json "wikidata_entity_Q157555.json";
    summary_fr = Check.json "wikipedia_summary_fr_Digitalis_purpurea.json";
    (* fr has no uses section: the stored uses member is the en
       extract. *)
    uses = Check.json "wikipedia_extract_en_Digitalis_purpurea.json";
    plantuse_page = Check.json "plantuse_page_digitalis_purpurea.json";
  }

let arnica =
  {
    species_body = Check.json "gbif_species_5405976.json";
    vernacular_names = Check.json "gbif_vernacular_names_5405976.json";
    distributions = Check.json "gbif_distributions_5405976.json";
    occurrence_count = Check.json "gbif_occurrence_count_5405976.json";
    plantnet_media = Check.json "gbif_plantnet_media_5405976.json";
    search_p846 = Check.json "wikidata_search_p846_5405976.json";
    entity = Check.json "wikidata_entity_Q207848.json";
    summary_fr = Check.json "wikipedia_summary_fr_Arnica_montana.json";
    (* fr has a uses section: the stored uses member is
       the fr extract. *)
    uses = Check.json "wikipedia_extract_fr_Arnica_des_montagnes.json";
    (* Arnica's plantuse page exists but has no box nor prose: a row is
       still stored (a page was found), the projected Pl@ntUse part is
       None. *)
    plantuse_page = Check.json "plantuse_page_arnica_montana.json";
  }

let gbif_payload s =
  Payload.gbif ~species:(Some s.species_body)
    ~vernacular_names:(Some s.vernacular_names)
    ~distributions:(Some s.distributions)
    ~occurrence_count:(Some s.occurrence_count)

let plantnet_payload s = Payload.plantnet ~media:(Some s.plantnet_media)

let wikidata_payload s =
  Payload.wikidata ~search:(Some s.search_p846) ~entity:(Some s.entity)

let wikipedia_payload s =
  Payload.wikipedia ~summary:(Some s.summary_fr) ~uses:(Some s.uses)

let plantuse_payload s = Payload.plantuse ~page:(Some s.plantuse_page)

let rows_of s =
  [
    reference_row ~source:Source.Gbif ~fetched_at:t_gbif (gbif_payload s);
    reference_row ~source:Source.Plantnet ~fetched_at:t_other
      (plantnet_payload s);
    reference_row ~source:Source.Wikidata ~fetched_at:t_other
      (wikidata_payload s);
    reference_row ~source:Source.Wikipedia ~fetched_at:t_other
      (wikipedia_payload s);
    reference_row ~source:Source.Plantuse ~fetched_at:t_other
      (plantuse_payload s);
  ]

let project ?(plant_refs = []) references =
  Projection.project ~references ~plant_refs

(* ---------- JSON renderings, for readable diffs ---------- *)

let source_json s = `String (Source.to_string s)
let sources_json l = `List (List.map source_json l)
let opt f = function None -> `Null | Some v -> f v

let status_json : Gbif.Status.t -> Yojson.Safe.t = function
  | Accepted -> `String "Accepted"
  | Doubtful -> `String "Doubtful"
  | Synonym -> `String "Synonym"
  | Other s -> `Assoc [("Other", `String s)]

let taxon_json (t : Gbif.Taxon.t) =
  `Assoc
    [
      ("key", `Int t.key);
      ("scientific_name", `String t.scientific_name);
      ("family", opt (fun s -> `String s) t.family);
      ("status", opt status_json t.status);
    ]

let cited_json value_json (c : 'a Projection.cited option) =
  match c with
  | None -> `Null
  | Some {Projection.value; sources} ->
      `Assoc [("value", value_json value); ("sources", sources_json sources)]

let link source url : Projection.link = {source; url}

let link_json (l : Projection.link) =
  `Assoc [("source", source_json l.source); ("url", `String l.url)]

let area code name : Projection.area = {code; name}

let area_json (a : Projection.area) =
  `Assoc [("code", opt (fun s -> `String s) a.code); ("name", `String a.name)]

let areas_json l = `List (List.map area_json l)
let links_json l = `List (List.map link_json l)
let field_json (f : Projection.Field.t) = `String (Projection.Field.to_string f)
let fields_json l = `List (List.map field_json l)
let ptime = Alcotest.testable Ptime.pp Ptime.equal

(* ---------- helpers on the result ---------- *)

let problem_strings (problems : Projection.problem list) =
  List.map
    (fun (p : Projection.problem) ->
      Payload.name p.part ^ ": " ^ Decode.error_to_string p.error)
    problems

let names_of (lang : Projection.Lang.t) (v : Projection.vernacular list) =
  List.find_map
    (fun (x : Projection.vernacular) ->
      match x.lang = lang with true -> Some x.names | false -> None)
    v

let link_url source (links : Projection.link list) =
  List.find_map
    (fun (l : Projection.link) ->
      match
        String.equal (Source.to_string l.source) (Source.to_string source)
      with
      | true -> Some l.url
      | false -> None)
    links

let link_url_exn what source links =
  match link_url source links with
  | Some url -> url
  | None -> Alcotest.failf "%s: no %s link" what (Source.to_string source)

(* ---------- both spike species ---------- *)

let digitalis_tests =
  let proj = project (rows_of digitalis) in
  [
    ( "taxon: key, scientific_name, family, sources [Gbif]",
      `Quick,
      fun () ->
        match proj.taxon with
        | Some {value; sources} ->
            Alcotest.(check int) "key" 5414995 value.key;
            Alcotest.(check string)
              "scientific_name" "Digitalis purpurea L." value.scientific_name;
            Alcotest.(check (option string))
              "family" (Some "Plantaginaceae") value.family;
            Alcotest.(check Testable.yojson)
              "sources"
              (sources_json [Source.Gbif])
              (sources_json sources)
        | None -> Alcotest.fail "taxon is None" );
    ( "vernacular: fr, en, de, it in order, sources [Gbif; Wikidata]",
      `Quick,
      fun () ->
        match proj.vernacular with
        | Some {value; sources} ->
            Alcotest.(check (list string))
              "languages, in order" ["fr"; "en"; "de"; "it"]
              (List.map
                 (fun (v : Projection.vernacular) ->
                   Projection.Lang.to_string v.lang)
                 value);
            Alcotest.(check (option (list string)))
              "fr"
              (Some ["Digitale pourpre"; "Digitale pourprée"; "grande digitale"])
              (names_of Fr value);
            Alcotest.(check (option (list string)))
              "en"
              (Some ["Foxglove"; "Purple Foxglove"; "Common Foxglove"])
              (names_of En value);
            Alcotest.(check (option (list string)))
              "de" (Some ["Roter Fingerhut"]) (names_of De value);
            Alcotest.(check (option (list string)))
              "it" (Some ["Digitale rossa"]) (names_of It value);
            Alcotest.(check Testable.yojson)
              "sources"
              (sources_json [Source.Gbif; Source.Wikidata])
              (sources_json sources)
        | None -> Alcotest.fail "vernacular is None" );
    ( "origin: 12 native starting as recorded, 80 introduced starting as \
       recorded, codes kept",
      `Quick,
      fun () ->
        match proj.origin with
        | Some {value; sources = _} ->
            Alcotest.(check int) "native count" 12 (List.length value.native);
            Alcotest.(check Testable.yojson)
              "native, first five"
              (areas_json
                 [
                   area (Some "BGM") "Belgium";
                   area (Some "COR") "Corse";
                   area (Some "CZE") "Czechia-Slovakia";
                   area (Some "FRA") "France";
                   area (Some "GER") "Germany";
                 ])
              (areas_json (List.filteri (fun i _ -> i < 5) value.native));
            Alcotest.(check int)
              "introduced count" 80
              (List.length value.introduced);
            Alcotest.(check Testable.yojson)
              "introduced, first three"
              (areas_json
                 [
                   area (Some "AGE") "Argentina Northeast";
                   area (Some "AGW") "Argentina Northwest";
                   area (Some "AGS") "Argentina South";
                 ])
              (areas_json (List.filteri (fun i _ -> i < 3) value.introduced))
        | None -> Alcotest.fail "origin is None" );
    ( "red_list is None (no global IUCN assessment)",
      `Quick,
      fun () ->
        Alcotest.(check bool) "red_list" true (Option.is_none proj.red_list) );
    ( "toxicity: the fr summary's first matching sentence, sources [Wikipedia]",
      `Quick,
      fun () ->
        match proj.toxicity with
        | Some {value; sources} ->
            Alcotest.(check string)
              "value" "La plante est extrêmement toxique." value;
            Alcotest.(check Testable.yojson)
              "sources"
              (sources_json [Source.Wikipedia])
              (sources_json sources)
        | None -> Alcotest.fail "toxicity is None" );
    ( "organ_photos: Flower, Leaf, Habit (no Fruit), sources [Plantnet], \
       cc-by-sa",
      `Quick,
      fun () ->
        match proj.organ_photos with
        | Some {value; sources} ->
            Alcotest.(check (list string))
              "organs, in Organ.all order"
              ["flower"; "leaf"; "habit"]
              (List.filter_map
                 (fun (i : Gbif.Image.t) -> Option.map Organ.to_string i.organ)
                 value);
            List.iter
              (fun (i : Gbif.Image.t) ->
                Alcotest.(check string) "licence" "cc-by-sa" i.licence)
              value;
            Alcotest.(check Testable.yojson)
              "sources"
              (sources_json [Source.Plantnet])
              (sources_json sources)
        | None -> Alcotest.fail "organ_photos is None" );
    ( "links, in order",
      `Quick,
      fun () ->
        Alcotest.(check Testable.yojson)
          "links"
          (links_json
             [
               link Source.Gbif "https://www.gbif.org/species/5414995";
               link Source.Wikipedia
                 "https://fr.wikipedia.org/wiki/Digitalis_purpurea";
               link Source.Powo
                 "https://powo.science.kew.org/taxon/urn:lsid:ipni.org:names:802077-1";
               link Source.Taxref "https://inpn.mnhn.fr/espece/cd_nom/94959";
               link Source.Tela "https://www.tela-botanica.org/bdtfx-nn-22437";
               link Source.Inat "https://www.inaturalist.org/taxa/53983";
               link Source.Eppo "https://gd.eppo.int/taxon/DIKPU";
               (* Plantuse is last, its page was found. *)
               link Source.Plantuse (Source_url.plantuse "Digitalis purpurea");
             ])
          (links_json proj.links) );
    ( "fetched_at is the gbif row's, problems is []",
      `Quick,
      fun () ->
        Alcotest.(check (option ptime))
          "fetched_at" (Some t_gbif) proj.fetched_at;
        Alcotest.(check (list string))
          "problems" []
          (problem_strings proj.problems) );
    ( "empty_fields: the regional six plus red_list",
      `Quick,
      fun () ->
        Alcotest.(check Testable.yojson)
          "empty_fields"
          (fields_json
             Projection.Field.
               [
                 Life_form;
                 Fr_status;
                 Fr_protection;
                 Red_list;
                 Flowering_months;
                 Habitat;
                 Ecology;
               ])
          (fields_json (Projection.empty_fields proj)) );
    ( "life_form, flowering_months, habitat are None without a Tela row",
      `Quick,
      fun () ->
        Alcotest.(check bool) "life_form" true (Option.is_none proj.life_form);
        Alcotest.(check bool)
          "flowering_months" true
          (Option.is_none proj.flowering_months);
        Alcotest.(check bool) "habitat" true (Option.is_none proj.habitat) );
  ]

let arnica_tests =
  let proj = project (rows_of arnica) in
  [
    ( "taxon: key, family",
      `Quick,
      fun () ->
        match proj.taxon with
        | Some {value; sources = _} ->
            Alcotest.(check int) "key" 5405976 value.key;
            Alcotest.(check (option string))
              "family" (Some "Asteraceae") value.family
        | None -> Alcotest.fail "taxon is None" );
    ( "vernacular: fr, en, de, it",
      `Quick,
      fun () ->
        match proj.vernacular with
        | Some {value; sources = _} ->
            Alcotest.(check (option (list string)))
              "fr"
              (Some ["Arnica"; "Arnica des montagnes"; "Herbe aux prêcheurs"])
              (names_of Fr value);
            Alcotest.(check (option (list string)))
              "en"
              (Some ["Mountain Arnica"; "European arnica"; "Leopard's Bane"])
              (names_of En value);
            Alcotest.(check (option (list string)))
              "de"
              (Some ["Berg-Wohlverleih"; "Arnika"; "Wohlverleih"])
              (names_of De value);
            Alcotest.(check (option (list string)))
              "it" (Some ["Arnica"]) (names_of It value)
        | None -> Alcotest.fail "vernacular is None" );
    ( "origin: 21 native starting as recorded, introduced is West Himalaya, \
       codes kept",
      `Quick,
      fun () ->
        match proj.origin with
        | Some {value; sources = _} ->
            Alcotest.(check int) "native count" 21 (List.length value.native);
            Alcotest.(check Testable.yojson)
              "native, first three"
              (areas_json
                 [
                   area (Some "AUT") "Austria";
                   area (Some "BLT") "Baltic States";
                   area (Some "BLR") "Belarus";
                 ])
              (areas_json (List.filteri (fun i _ -> i < 3) value.native));
            Alcotest.(check Testable.yojson)
              "introduced"
              (areas_json [area (Some "WHM") "West Himalaya"])
              (areas_json value.introduced)
        | None -> Alcotest.fail "origin is None" );
    ( "red_list is LEAST_CONCERN, sources [Gbif]",
      `Quick,
      fun () ->
        match proj.red_list with
        | Some {value; sources} ->
            Alcotest.(check string) "value" "LEAST_CONCERN" value;
            Alcotest.(check Testable.yojson)
              "sources"
              (sources_json [Source.Gbif])
              (sources_json sources)
        | None -> Alcotest.fail "red_list is None" );
    ( "toxicity is None (not in the fr summary)",
      `Quick,
      fun () ->
        Alcotest.(check bool) "toxicity" true (Option.is_none proj.toxicity) );
    ( "organ_photos: Flower, Leaf, Fruit, Habit",
      `Quick,
      fun () ->
        match proj.organ_photos with
        | Some {value; sources = _} ->
            Alcotest.(check (list string))
              "organs, in Organ.all order"
              ["flower"; "leaf"; "fruit"; "habit"]
              (List.filter_map
                 (fun (i : Gbif.Image.t) -> Option.map Organ.to_string i.organ)
                 value)
        | None -> Alcotest.fail "organ_photos is None" );
    ( "links, in order",
      `Quick,
      fun () ->
        Alcotest.(check Testable.yojson)
          "links"
          (links_json
             [
               link Source.Gbif "https://www.gbif.org/species/5405976";
               link Source.Wikipedia
                 "https://fr.wikipedia.org/wiki/Arnica_des_montagnes";
               link Source.Powo
                 "https://powo.science.kew.org/taxon/urn:lsid:ipni.org:names:30090722-2";
               link Source.Taxref "https://inpn.mnhn.fr/espece/cd_nom/83874";
               link Source.Tela "https://www.tela-botanica.org/bdtfx-nn-6648";
               link Source.Inat "https://www.inaturalist.org/taxa/56229";
               link Source.Eppo "https://gd.eppo.int/taxon/ARXMO";
               (* A page was found: the link shows even when it has no
                  uses box and no prose. *)
               link Source.Plantuse (Source_url.plantuse "Arnica montana");
             ])
          (links_json proj.links) );
    ( "fetched_at is the gbif row's, problems is []",
      `Quick,
      fun () ->
        Alcotest.(check (option ptime))
          "fetched_at" (Some t_gbif) proj.fetched_at;
        Alcotest.(check (list string))
          "problems" []
          (problem_strings proj.problems) );
    ( "empty_fields: the regional six plus toxicity",
      `Quick,
      fun () ->
        Alcotest.(check Testable.yojson)
          "empty_fields"
          (fields_json
             Projection.Field.
               [
                 Life_form;
                 Fr_status;
                 Fr_protection;
                 Flowering_months;
                 Habitat;
                 Ecology;
                 Toxicity;
               ])
          (fields_json (Projection.empty_fields proj)) );
    ( "life_form, flowering_months, habitat are None without a Tela row",
      `Quick,
      fun () ->
        Alcotest.(check bool) "life_form" true (Option.is_none proj.life_form);
        Alcotest.(check bool)
          "flowering_months" true
          (Option.is_none proj.flowering_months);
        Alcotest.(check bool) "habitat" true (Option.is_none proj.habitat) );
  ]

(* ---------- degradation and rules ---------- *)

let no_rows_is_empty () =
  let proj = project [] in
  Alcotest.(check Testable.yojson)
    "taxon" `Null
    (cited_json taxon_json proj.taxon);
  Alcotest.(check bool) "vernacular" true (Option.is_none proj.vernacular);
  Alcotest.(check bool) "origin" true (Option.is_none proj.origin);
  Alcotest.(check bool) "red_list" true (Option.is_none proj.red_list);
  Alcotest.(check bool) "toxicity" true (Option.is_none proj.toxicity);
  Alcotest.(check bool) "organ_photos" true (Option.is_none proj.organ_photos);
  Alcotest.(check (list string))
    "links" []
    (List.map (fun (l : Projection.link) -> l.url) proj.links);
  Alcotest.(check (option ptime)) "fetched_at" None proj.fetched_at;
  Alcotest.(check Testable.yojson)
    "empty_fields"
    (fields_json Projection.Field.all)
    (fields_json (Projection.empty_fields proj))

let only_gbif_row () =
  let proj =
    project
      [
        reference_row ~source:Source.Gbif ~fetched_at:t_gbif
          (gbif_payload digitalis);
      ]
  in
  (match proj.taxon with
  | Some {value; sources} ->
      Alcotest.(check int) "taxon key" 5414995 value.key;
      Alcotest.(check Testable.yojson)
        "taxon sources"
        (sources_json [Source.Gbif])
        (sources_json sources)
  | None -> Alcotest.fail "taxon is None");
  (match proj.vernacular with
  | Some {sources; _} ->
      Alcotest.(check Testable.yojson)
        "vernacular sources"
        (sources_json [Source.Gbif])
        (sources_json sources)
  | None -> Alcotest.fail "vernacular is None");
  Alcotest.(check bool) "origin is set" true (Option.is_some proj.origin);
  Alcotest.(check bool) "toxicity is None" true (Option.is_none proj.toxicity);
  Alcotest.(check bool)
    "organ_photos is None" true
    (Option.is_none proj.organ_photos);
  Alcotest.(check Testable.yojson)
    "links = [Gbif] only"
    (links_json [link Source.Gbif "https://www.gbif.org/species/5414995"])
    (links_json proj.links)

let gbif_species_broken () =
  let payload =
    Payload.gbif
      ~species:(Some (`String "oops"))
      ~vernacular_names:(Some digitalis.vernacular_names)
      ~distributions:(Some digitalis.distributions)
      ~occurrence_count:(Some digitalis.occurrence_count)
  in
  let proj =
    project [reference_row ~source:Source.Gbif ~fetched_at:t_gbif payload]
  in
  Alcotest.(check bool) "taxon is None" true (Option.is_none proj.taxon);
  (match proj.problems with
  | [{part = Payload.Gbif_species; error = Decode.Unexpected _}] -> ()
  | problems ->
      Alcotest.failf "expected one Gbif_species Unexpected problem, got [%s]"
        (String.concat "; " (problem_strings problems)));
  Alcotest.(check bool)
    "origin is still projected" true
    (Option.is_some proj.origin);
  Alcotest.(check bool)
    "no Gbif link" true
    (Option.is_none (link_url Source.Gbif proj.links))

let problems_in_payload_all_order () =
  let gbif =
    Payload.gbif ~species:None ~vernacular_names:None ~distributions:None
      ~occurrence_count:(Some (`String "oops"))
  in
  let wikidata =
    Payload.wikidata ~search:None ~entity:(Some (`String "oops"))
  in
  let proj =
    project
      [
        reference_row ~source:Source.Wikidata ~fetched_at:t_other wikidata;
        reference_row ~source:Source.Gbif ~fetched_at:t_gbif gbif;
      ]
  in
  Alcotest.(check (list string))
    "the failing parts, in Payload.all order whatever the row order"
    ["occurrence_count"; "entity"]
    (List.map
       (fun (p : Projection.problem) -> Payload.name p.part)
       proj.problems)

let soft_deleted_wikipedia_row_ignored () =
  let proj =
    project
      [
        reference_row ~source:Source.Wikipedia ~fetched_at:t_other
          ~deleted_at:t_other
          (wikipedia_payload digitalis);
      ]
  in
  Alcotest.(check bool) "toxicity is None" true (Option.is_none proj.toxicity);
  Alcotest.(check bool)
    "no Wikipedia link" true
    (Option.is_none (link_url Source.Wikipedia proj.links))

let powo_row_ignored () =
  let powo_row =
    reference_row ~source:Source.Powo ~fetched_at:t_gbif
      (`Assoc [("x", `Int 1)])
  in
  let proj = project [powo_row] in
  Alcotest.(check (option ptime)) "fetched_at stays None" None proj.fetched_at;
  Alcotest.(check bool) "taxon stays None" true (Option.is_none proj.taxon);
  Alcotest.(check Testable.yojson)
    "links stays []" (links_json []) (links_json proj.links);
  Alcotest.(check Testable.yojson)
    "empty_fields is Field.all"
    (fields_json Projection.Field.all)
    (fields_json (Projection.empty_fields proj))

let fetched_at_is_the_minimum () =
  let earlier = time "2026-11-01T09:00:00Z" in
  let later = time "2026-11-01T10:30:00Z" in
  let proj =
    project
      [
        reference_row ~source:Source.Gbif ~fetched_at:later
          (gbif_payload digitalis);
        reference_row ~source:Source.Wikipedia ~fetched_at:earlier
          (wikipedia_payload digitalis);
      ]
  in
  Alcotest.(check (option ptime))
    "fetched_at is the earlier row's" (Some earlier) proj.fetched_at

let fetched_at_ignores_failed_rows () =
  let earlier = time "2026-11-01T09:00:00Z" in
  let failed =
    reference_row ~status:Reference.Status.Failed ~source:Source.Plantnet
      ~fetched_at:earlier (`Assoc [])
  in
  Alcotest.(check (option ptime))
    "the complete row's, not the failed one's" (Some t_gbif)
    (project
       [
         reference_row ~source:Source.Gbif ~fetched_at:t_gbif
           (gbif_payload digitalis);
         failed;
       ])
      .fetched_at;
  Alcotest.(check (option ptime))
    "only failed rows: None" None (project [failed]).fetched_at

let plant_ref_rules () =
  let override_url = "https://www.gbif.org/species/1" in
  let plant_refs =
    [
      plant_ref ~source:Source.Gbif ~external_id:"1" ~url:override_url t_other;
      plant_ref ~source:Source.Plantnet ~external_id:"p1"
        ~url:
          "https://identify.plantnet.org/species/Digitalis%20purpurea%20L./data"
        t_other;
      plant_ref ~source:Source.Inat ~external_id:"0"
        ~url:"https://www.inaturalist.org/taxa/0" ~deleted_at:t_other t_other;
    ]
  in
  let proj = project ~plant_refs (rows_of digitalis) in
  Alcotest.(check (option string))
    "a live Gbif plant ref replaces the derived link" (Some override_url)
    (link_url Source.Gbif proj.links);
  Alcotest.(check (option string))
    "a live Plantnet plant ref adds a link"
    (Some "https://identify.plantnet.org/species/Digitalis%20purpurea%20L./data")
    (link_url Source.Plantnet proj.links);
  (match proj.links with
  | {source = Source.Gbif; _} :: {source = Source.Plantnet; _} :: _ -> ()
  | links ->
      Alcotest.failf
        "expected Gbif then Plantnet (link_order index 1) first, got %s"
        (Yojson.Safe.to_string (links_json links)));
  Alcotest.(check (option string))
    "a soft-deleted Inat plant ref is ignored: the derived link stays"
    (Some "https://www.inaturalist.org/taxa/53983")
    (link_url Source.Inat proj.links)

let source_url_classification () =
  List.iter
    (fun (url, expected) ->
      Alcotest.(check bool)
        (url ^ " classifies back") true
        (Link.equal (Link.classify url) expected))
    [
      (Source_url.taxref 94959, Link.Inpn 94959);
      (Source_url.tela 22437, Link.Tela 22437);
      (Source_url.inat 53983, Link.Inat 53983);
      ( Source_url.powo "urn:lsid:ipni.org:names:802077-1",
        Link.Powo "urn:lsid:ipni.org:names:802077-1" );
      (Source_url.powo "abc 1", Link.Powo "abc 1");
      ( Source_url.plantnet "Digitalis purpurea L.",
        Link.Plantnet "Digitalis purpurea L." );
      ( Source_url.wikipedia ~lang:"fr" "Ail (plante)",
        Link.Wikipedia {lang = "fr"; title = "Ail (plante)"} );
    ];
  Alcotest.(check string)
    "an IPNI lsid is written as is"
    "https://powo.science.kew.org/taxon/urn:lsid:ipni.org:names:802077-1"
    (Source_url.powo "urn:lsid:ipni.org:names:802077-1")

let link_classification () =
  let case ~what url expected =
    Alcotest.(check bool)
      (Printf.sprintf "%s: %s classifies as expected" what url)
      true
      (Link.equal (Link.classify url) expected)
  in
  let proj_digitalis = project (rows_of digitalis) in
  let proj_arnica = project (rows_of arnica) in
  List.iter
    (fun (what, url, expected) -> case ~what url expected)
    [
      ( "Digitalis Gbif",
        link_url_exn "proj_digitalis" Source.Gbif proj_digitalis.links,
        Link.Gbif 5414995 );
      ( "Digitalis Wikipedia",
        link_url_exn "proj_digitalis" Source.Wikipedia proj_digitalis.links,
        Link.Wikipedia {lang = "fr"; title = "Digitalis purpurea"} );
      ( "Digitalis Powo",
        link_url_exn "proj_digitalis" Source.Powo proj_digitalis.links,
        Link.Powo "urn:lsid:ipni.org:names:802077-1" );
      ( "Digitalis Taxref",
        link_url_exn "proj_digitalis" Source.Taxref proj_digitalis.links,
        Link.Inpn 94959 );
      ( "Digitalis Tela",
        link_url_exn "proj_digitalis" Source.Tela proj_digitalis.links,
        Link.Tela 22437 );
      ( "Digitalis Inat",
        link_url_exn "proj_digitalis" Source.Inat proj_digitalis.links,
        Link.Inat 53983 );
      ( "Arnica Gbif",
        link_url_exn "proj_arnica" Source.Gbif proj_arnica.links,
        Link.Gbif 5405976 );
      ( "Arnica Wikipedia",
        link_url_exn "proj_arnica" Source.Wikipedia proj_arnica.links,
        Link.Wikipedia {lang = "fr"; title = "Arnica des montagnes"} );
      ( "Arnica Powo",
        link_url_exn "proj_arnica" Source.Powo proj_arnica.links,
        Link.Powo "urn:lsid:ipni.org:names:30090722-2" );
      ( "Arnica Taxref",
        link_url_exn "proj_arnica" Source.Taxref proj_arnica.links,
        Link.Inpn 83874 );
      ( "Arnica Tela",
        link_url_exn "proj_arnica" Source.Tela proj_arnica.links,
        Link.Tela 6648 );
      ( "Arnica Inat",
        link_url_exn "proj_arnica" Source.Inat proj_arnica.links,
        Link.Inat 56229 );
    ]

(* ---------- toxicity ---------- *)

let toxicity_en_summary () =
  let proj =
    project
      [
        reference_row ~source:Source.Wikipedia ~fetched_at:t_other
          (Payload.wikipedia
             ~summary:
               (Some (Check.json "wikipedia_summary_en_Digitalis_purpurea.json"))
             ~uses:None);
      ]
  in
  match proj.toxicity with
  | Some {value; _} ->
      Alcotest.(check string)
        "the en summary's first sentence"
        "Digitalis purpurea, the foxglove or common foxglove, is a toxic \
         species of flowering plant in the plantain family Plantaginaceae, \
         native to and widespread throughout most of temperate Europe."
        value
  | None -> Alcotest.fail "toxicity is None"

let toxicity_disambiguation_is_none () =
  let proj =
    project
      [
        reference_row ~source:Source.Wikipedia ~fetched_at:t_other
          (Payload.wikipedia
             ~summary:(Some (Check.json "wikipedia_summary_fr_Lis.json"))
             ~uses:None);
      ]
  in
  Alcotest.(check bool) "toxicity is None" true (Option.is_none proj.toxicity);
  Alcotest.(check bool)
    "no Wikipedia link" true
    (Option.is_none (link_url Source.Wikipedia proj.links))

let toxicity_description_only_match () =
  let summary =
    `Assoc
      [
        ("type", `String "standard");
        ("title", `String "Exemple");
        ("description", `String "plante toxique");
        ("extract", `String "Ceci est une plante herbacée. Elle fleurit en été.");
      ]
  in
  let proj =
    project
      [
        reference_row ~source:Source.Wikipedia ~fetched_at:t_other
          (Payload.wikipedia ~summary:(Some summary) ~uses:None);
      ]
  in
  match proj.toxicity with
  | Some {value; _} ->
      Alcotest.(check string) "the description" "plante toxique" value
  | None -> Alcotest.fail "toxicity is None"

(* ---------- vernacular (inline) ---------- *)

let vernacular_page results =
  `Assoc [("results", `List results); ("endOfRecords", `Bool true)]

let vernacular_result ?language name =
  `Assoc
    (("vernacularName", `String name)
    :: (match language with None -> [] | Some l -> [("language", `String l)]))

let vernacular_of_gbif_page page =
  let payload =
    Payload.gbif ~species:None ~vernacular_names:(Some page) ~distributions:None
      ~occurrence_count:None
  in
  let proj =
    project [reference_row ~source:Source.Gbif ~fetched_at:t_gbif payload]
  in
  proj.vernacular

let vernacular_tie_by_position () =
  match
    vernacular_of_gbif_page
      (vernacular_page
         [
           vernacular_result ~language:"fra" "b, a";
           vernacular_result ~language:"fra" "A";
           vernacular_result ~language:"fra" "b";
           vernacular_result ~language:"nld" "x";
         ])
  with
  | Some {value; _} ->
      Alcotest.(check (option (list string)))
        "fr: b first (its first vote comes first), not alphabetical"
        (Some ["b"; "a"])
        (names_of Fr value);
      Alcotest.(check (list string))
        "nld is dropped: fr is the only language" ["fr"]
        (List.map
           (fun (v : Projection.vernacular) -> Projection.Lang.to_string v.lang)
           value)
  | None -> Alcotest.fail "vernacular is None"

let vernacular_keeps_top_three () =
  match
    vernacular_of_gbif_page
      (vernacular_page
         (List.map
            (fun n -> vernacular_result ~language:"fra" n)
            ["A1"; "B1"; "C1"; "D1"]))
  with
  | Some {value; _} ->
      Alcotest.(check (option (list string)))
        "fr keeps the first three"
        (Some ["A1"; "B1"; "C1"])
        (names_of Fr value)
  | None -> Alcotest.fail "vernacular is None"

let vernacular_by_count () =
  match
    vernacular_of_gbif_page
      (vernacular_page
         (List.map
            (fun n -> vernacular_result ~language:"fra" n)
            ["x"; "y"; "z"; "w"; "W"]))
  with
  | Some {value; _} ->
      Alcotest.(check (option (list string)))
        "fr: the two-vote group first, then by first vote"
        (Some ["w"; "x"; "y"])
        (names_of Fr value)
  | None -> Alcotest.fail "vernacular is None"

(* ---------- distributions (inline) ---------- *)

let wcvp = "The World Checklist of Vascular Plants (WCVP)"
let iucn = "The IUCN Red List of Threatened Species"

(* without ~location_id: no locationId member, read as code = None *)
let distribution ?location_id ?locality ?country ?status ?means ?threat source =
  `Assoc
    (List.filter_map
       (fun (k, v) -> Option.map (fun v -> (k, `String v)) v)
       [
         ("locationId", location_id);
         ("locality", locality);
         ("country", country);
         ("status", status);
         ("establishmentMeans", means);
         ("threatStatus", threat);
         ("source", Some source);
       ])

let gbif_row ?species ?distributions () =
  reference_row ~source:Source.Gbif ~fetched_at:t_gbif
    (Payload.gbif ~species ~vernacular_names:None ~distributions
       ~occurrence_count:None)

let origin_json (o : Projection.origin) =
  `Assoc
    [("native", areas_json o.native); ("introduced", areas_json o.introduced)]

let origin_and_red_list_rules () =
  let page =
    vernacular_page
      [
        distribution ~locality:"France" wcvp;
        distribution ~locality:"Spain" ~status:"ABSENT" wcvp;
        distribution ~locality:"Italy" ~status:"EXCLUDED" wcvp;
        distribution ~locality:"Malta" ~status:"DOUBTFUL" wcvp;
        distribution ~locality:"France" wcvp;
        distribution ~locality:"Chile" ~means:"INTRODUCED" wcvp;
        distribution ~locality:"Chile" ~means:"INTRODUCED" wcvp;
        distribution ~locality:"Peru" ~means:"NATURALISED" wcvp;
        distribution ~locality:"Kenya" ~means:"UNCERTAIN" wcvp;
        distribution ~locality:"Norway" ~status:"PRESENT" ~means:"NATIVE" wcvp;
        distribution ~locality:"Japan" ~means:"INTRODUCED" "DAISIE";
        distribution ~country:"FR" ~threat:"VULNERABLE" iucn;
        distribution ~locality:"France" ~threat:"ENDANGERED"
          "IUCN Red List Vascular Plants (2018, metropolitan France)";
        distribution ~locality:"Global" ~threat:"NEAR_THREATENED" iucn;
      ]
  in
  let proj = project [gbif_row ~distributions:page ()] in
  Alcotest.(check Testable.yojson)
    "origin: present WCVP rows, deduplicated, UNCERTAIN in neither list, no \
     locationId so no code"
    (cited_json origin_json
       (Some
          {
            Projection.value =
              {
                native = [area None "France"; area None "Norway"];
                introduced = [area None "Chile"; area None "Peru"];
              };
            sources = [Source.Gbif];
          }))
    (cited_json origin_json proj.origin);
  Alcotest.(check (option string))
    "red_list: the global row of the IUCN source" (Some "NEAR_THREATENED")
    (Option.map (fun (c : string Projection.cited) -> c.value) proj.red_list)

let origin_area_code_rules () =
  let native_of distributions =
    match (project [gbif_row ~distributions ()]).origin with
    | Some {value; _} -> value.native
    | None -> Alcotest.fail "origin is None"
  in
  Alcotest.(check Testable.yojson)
    "a TDWG-prefixed locationId gives its suffix as the code"
    (areas_json [area (Some "FRA") "France"])
    (areas_json
       (native_of
          (vernacular_page
             [distribution ~location_id:"TDWG:FRA" ~locality:"France" wcvp])));
  Alcotest.(check Testable.yojson)
    "a locationId without the TDWG: prefix gives no code"
    (areas_json [area None "France"])
    (areas_json
       (native_of
          (vernacular_page
             [distribution ~location_id:"France" ~locality:"France" wcvp])));
  Alcotest.(check Testable.yojson)
    "a locationId of exactly \"TDWG:\" (nothing after the prefix) gives no code"
    (areas_json [area None "France"])
    (areas_json
       (native_of
          (vernacular_page
             [distribution ~location_id:"TDWG:" ~locality:"France" wcvp])));
  Alcotest.(check Testable.yojson)
    "two rows with the same code and different localities: one area, the first \
     kept"
    (areas_json [area (Some "FRA") "France"])
    (areas_json
       (native_of
          (vernacular_page
             [
               distribution ~location_id:"TDWG:FRA" ~locality:"France" wcvp;
               distribution ~location_id:"TDWG:FRA" ~locality:"Francia" wcvp;
             ])));
  Alcotest.(check Testable.yojson)
    "two rows without a code and the same locality: one area"
    (areas_json [area None "France"])
    (areas_json
       (native_of
          (vernacular_page
             [
               distribution ~locality:"France" wcvp;
               distribution ~locality:"France" wcvp;
             ])));
  Alcotest.(check Testable.yojson)
    "a coded row, then an uncoded one of the same locality: one area, the \
     coded one"
    (areas_json [area (Some "FRA") "France"])
    (areas_json
       (native_of
          (vernacular_page
             [
               distribution ~location_id:"TDWG:FRA" ~locality:"France" wcvp;
               distribution ~locality:"France" wcvp;
             ])));
  Alcotest.(check Testable.yojson)
    "an uncoded row, then a coded one of the same locality: one area, the \
     uncoded one"
    (areas_json [area None "France"])
    (areas_json
       (native_of
          (vernacular_page
             [
               distribution ~locality:"France" wcvp;
               distribution ~location_id:"TDWG:FRA" ~locality:"France" wcvp;
             ])));
  Alcotest.(check Testable.yojson)
    "two codes, the same locality: two areas"
    (areas_json
       [area (Some "CZE") "Czechoslovakia"; area (Some "SVK") "Czechoslovakia"])
    (areas_json
       (native_of
          (vernacular_page
             [
               distribution ~location_id:"TDWG:CZE" ~locality:"Czechoslovakia"
                 wcvp;
               distribution ~location_id:"TDWG:SVK" ~locality:"Czechoslovakia"
                 wcvp;
             ])))

let filled_family_and_ranges () =
  let species = `Assoc [("key", `Int 1); ("scientificName", `String "X y")] in
  let empty distributions =
    let proj = project [gbif_row ~species ~distributions ()] in
    List.filter
      (fun f ->
        List.mem f Projection.Field.[Family; Native_range; Introduced_range])
      (Projection.empty_fields proj)
  in
  Alcotest.(check Testable.yojson)
    "no family, introduced rows only"
    (fields_json Projection.Field.[Family; Native_range])
    (fields_json
       (empty
          (vernacular_page
             [distribution ~locality:"Chile" ~means:"INTRODUCED" wcvp])));
  Alcotest.(check Testable.yojson)
    "no family, native rows only"
    (fields_json Projection.Field.[Family; Introduced_range])
    (fields_json
       (empty (vernacular_page [distribution ~locality:"France" wcvp])))

(* [project] leaves these [None]; [filled] must still read them on a
   hand-built [t] (regional layer, architecture §6). *)
let filled_life_form_flowering_habitat () =
  let base = project [] in
  let cited value : _ Projection.cited = {value; sources = []} in
  let filled_of fields t = List.map (Projection.filled t) fields in
  let with_phrase_only =
    {
      base with
      Projection.life_form = Some (cited "Herbacée bisannuelle, 50-150 cm");
      flowering_months = Some (cited [6; 7; 8]);
      habitat = Some (cited {Projection.phrase = Some "Prairies"; chips = []});
    }
  in
  Alcotest.(check (list bool))
    "life_form, flowering_months, habitat filled; ecology not (no chips)"
    [true; true; true; false]
    (filled_of
       Projection.Field.[Life_form; Flowering_months; Habitat; Ecology]
       with_phrase_only);
  let with_chips_only =
    {
      base with
      Projection.habitat =
        Some (cited {Projection.phrase = None; chips = ["mi-ombre"]});
    }
  in
  Alcotest.(check (list bool))
    "ecology filled (chips), habitat not (no phrase)" [true; false]
    (filled_of Projection.Field.[Ecology; Habitat] with_chips_only)

(* ---------- rows ---------- *)

let first_live_row_of_a_source_wins () =
  let key references =
    Option.map
      (fun (c : Gbif.Taxon.t Projection.cited) -> c.value.key)
      (project references).taxon
  in
  let gbif ?status ?deleted_at s =
    reference_row ?status ?deleted_at ~source:Source.Gbif ~fetched_at:t_gbif
      (gbif_payload s)
  in
  Alcotest.(check (option int))
    "of two live rows, the first" (Some 5414995)
    (key [gbif digitalis; gbif arnica]);
  Alcotest.(check (option int))
    "a deleted row does not take the source's place" (Some 5414995)
    (key [gbif ~deleted_at:t_gbif arnica; gbif digitalis]);
  Alcotest.(check (option int))
    "a Failed row is still read" (Some 5414995)
    (key [gbif ~status:Reference.Status.Failed digitalis])

let every_part_broken () =
  let oops = Some (`String "oops") in
  let proj =
    project
      [
        reference_row ~source:Source.Gbif ~fetched_at:t_gbif
          (Payload.gbif ~species:oops ~vernacular_names:oops ~distributions:oops
             ~occurrence_count:oops);
        reference_row ~source:Source.Plantnet ~fetched_at:t_other
          (Payload.plantnet ~media:oops);
        reference_row ~source:Source.Wikidata ~fetched_at:t_other
          (Payload.wikidata ~search:oops ~entity:oops);
        reference_row ~source:Source.Wikipedia ~fetched_at:t_other
          (Payload.wikipedia ~summary:oops ~uses:oops);
        reference_row ~source:Source.Tela ~fetched_at:t_other
          (Payload.tela ~names:oops ~taxon:oops ~baseflor:oops);
        reference_row ~source:Source.Taxref ~fetched_at:t_other
          (Payload.taxref ~name:oops ~status:oops ~red_list:oops
             ~protections:oops);
        reference_row ~source:Source.Plantuse ~fetched_at:t_other
          (Payload.plantuse ~page:oops);
      ]
  in
  Alcotest.(check (list string))
    "one problem per part, in Payload.all order"
    (List.map Payload.name Payload.all)
    (List.map
       (fun (p : Projection.problem) -> Payload.name p.part)
       proj.problems)

let non_object_payload () =
  let proj =
    project [reference_row ~source:Source.Gbif ~fetched_at:t_gbif (`List [])]
  in
  Alcotest.(check (list string))
    "each gbif part is reported"
    (List.map
       (fun part ->
         Payload.name part
         ^ ": "
         ^ Decode.error_to_string
             (Decode.Unexpected {path = ""; expected = "object"}))
       (Payload.parts Source.Gbif))
    (problem_strings proj.problems);
  Alcotest.(check bool) "taxon is None" true (Option.is_none proj.taxon)

(* ---------- links (inline) ---------- *)

let statement value =
  `List
    [
      `Assoc
        [
          ("rank", `String "normal");
          ( "mainsnak",
            `Assoc
              [
                ("snaktype", `String "value");
                ("datavalue", `Assoc [("value", `String value)]);
              ] );
        ];
    ]

let entity_payload claims =
  Payload.wikidata ~search:None
    ~entity:
      (Some
         (`Assoc
            [
              ( "entities",
                `Assoc
                  [
                    ( "Q1",
                      `Assoc
                        [
                          ("id", `String "Q1");
                          ( "claims",
                            `Assoc
                              (List.map (fun (p, v) -> (p, statement v)) claims)
                          );
                        ] );
                  ] );
            ]))

let summary_payload ?(kind = "standard") ?description ?page extract =
  Payload.wikipedia
    ~summary:
      (Some
         (`Assoc
            (List.filter_map Fun.id
               [
                 Some ("type", `String kind);
                 Some ("title", `String "Exemple");
                 Option.map (fun d -> ("description", `String d)) description;
                 Option.map (fun e -> ("extract", `String e)) extract;
                 Option.map
                   (fun p ->
                     ( "content_urls",
                       `Assoc [("desktop", `Assoc [("page", `String p)])] ))
                   page;
               ])))
    ~uses:None

let malformed_ids_give_no_link () =
  let species = `Assoc [("key", `Int 1); ("scientificName", `String "X y")] in
  let links ~powo ~eppo ~page =
    (project
       [
         gbif_row ~species ();
         reference_row ~source:Source.Wikidata ~fetched_at:t_other
           (entity_payload
              [
                ("P5037", powo);
                ("P3031", eppo);
                ("P3186", "0");
                ("P3105", "0");
                ("P3151", "0");
              ]);
         reference_row ~source:Source.Wikipedia ~fetched_at:t_other
           (summary_payload ~page None);
       ])
      .links
  in
  let only_gbif =
    links_json [link Source.Gbif "https://www.gbif.org/species/1"]
  in
  Alcotest.(check Testable.yojson)
    "another urn, a lowercase EPPO code, zero ids, an http page" only_gbif
    (links_json
       (links ~powo:"urn:lsid:other.org:names:1" ~eppo:"dikpu"
          ~page:"http://fr.wikipedia.org/wiki/X_y"));
  Alcotest.(check Testable.yojson)
    "a POWO suffix with a letter, an EPPO code with a dash, a page off \
     Wikipedia"
    only_gbif
    (links_json
       (links ~powo:"urn:lsid:ipni.org:names:12a-1" ~eppo:"DIK-PU"
          ~page:"https://example.org/wiki/X_y"))

let stored_urls_are_checked () =
  let plant_refs =
    [
      plant_ref ~source:Source.Gbif ~external_id:"1" ~url:"javascript:alert(1)"
        t_other;
      plant_ref ~source:Source.Wikipedia ~external_id:"x"
        ~url:"http://fr.wikipedia.org/wiki/Digitalis_purpurea" t_other;
      plant_ref ~source:Source.Tela ~external_id:"1"
        ~url:"https://www.gbif.org/species/1" t_other;
      plant_ref ~source:Source.Inat ~external_id:"1"
        ~url:"https://www.inaturalist.org/taxa/1 https://example.org/" t_other;
      plant_ref ~source:Source.Eppo ~external_id:"XYZ"
        ~url:"https://gd.eppo.int/taxon/XYZ" t_other;
      plant_ref ~source:Source.Wikidata ~external_id:"Q157555"
        ~url:"https://www.wikidata.org/wiki/Q157555" t_other;
      plant_ref ~source:Source.Ipni ~external_id:"1"
        ~url:"https://example.org/ipni/1" t_other;
    ]
  in
  Alcotest.(check Testable.yojson)
    "a stored url off its source, not https or with a space gives way to the \
     derived link; EPPO and Wikidata ones on their host are kept"
    (links_json
       [
         link Source.Gbif "https://www.gbif.org/species/5414995";
         link Source.Wikipedia
           "https://fr.wikipedia.org/wiki/Digitalis_purpurea";
         link Source.Powo
           "https://powo.science.kew.org/taxon/urn:lsid:ipni.org:names:802077-1";
         link Source.Taxref "https://inpn.mnhn.fr/espece/cd_nom/94959";
         link Source.Tela "https://www.tela-botanica.org/bdtfx-nn-22437";
         link Source.Inat "https://www.inaturalist.org/taxa/53983";
         link Source.Eppo "https://gd.eppo.int/taxon/XYZ";
         link Source.Wikidata "https://www.wikidata.org/wiki/Q157555";
         link Source.Plantuse (Source_url.plantuse "Digitalis purpurea");
       ])
    (links_json (project ~plant_refs (rows_of digitalis)).links)

(* ---------- toxicity (inline) ---------- *)

let toxicity_of ?kind ?description extract =
  Option.map
    (fun (c : string Projection.cited) -> c.value)
    (project
       [
         reference_row ~source:Source.Wikipedia ~fetched_at:t_other
           (summary_payload ?kind ?description (Some extract));
       ])
      .toxicity

let toxicity_sentences () =
  let case what expected extract =
    Alcotest.(check (option string)) what expected (toxicity_of extract)
  in
  Alcotest.(check (option string))
    "a disambiguation page gives None even with a keyword" None
    (toxicity_of ~kind:"disambiguation"
       "Digitale peut désigner une plante toxique.");
  case "cut after \"! \"" (Some "Toute la plante est toxique.")
    "Attention ! Toute la plante est toxique. Elle fleurit.";
  case "cut after \"? \"" (Some "Non, elle est vénéneuse.")
    "Est-elle comestible ? Non, elle est vénéneuse. Fin.";
  case "not cut after an author initial"
    (Some "Digitalis purpurea L. est une plante toxique.")
    "Digitalis purpurea L. est une plante toxique. Elle fleurit.";
  case "cut at a newline" (Some "Toute la plante est toxique")
    "Premier paragraphe sans rien\nToute la plante est toxique";
  case "a negated sentence is quoted as is"
    (Some "Il n'est pas toxique pour les chats.")
    "Le Lilas est ornemental. Il n'est pas toxique pour les chats.";
  case "accented capitals are folded" (Some "LES BAIES SONT VÉNÉNEUSES.")
    "Une plante. LES BAIES SONT VÉNÉNEUSES."

(* ---------- Field ---------- *)

let field_all_and_to_string () =
  Alcotest.(check int)
    "Field.all has 14 elements" 14
    (List.length Projection.Field.all);
  let names = List.map Projection.Field.to_string Projection.Field.all in
  Alcotest.(check int)
    "to_string is distinct on every field" (List.length names)
    (List.length (List.sort_uniq String.compare names));
  Alcotest.(check string)
    "to_string is the snake_case constructor" "life_form"
    (Projection.Field.to_string Projection.Field.Life_form)

(* ---------- run ---------- *)

let case name f = (name, `Quick, f)

let rules_tests =
  [
    case
      "no rows: every option None, links [], fetched_at None, empty_fields is \
       Field.all"
      no_rows_is_empty;
    case
      "only the gbif row projects taxon/vernacular/origin, no toxicity, no \
       organ photos, links = [Gbif]"
      only_gbif_row;
    case
      "a broken gbif species member degrades only taxon, keeps the other gbif \
       parts, adds a problem"
      gbif_species_broken;
    case
      "a failing occurrence_count or wikidata entity is a problem, listed in \
       Payload.all order"
      problems_in_payload_all_order;
    case "a soft-deleted wikipedia row is ignored"
      soft_deleted_wikipedia_row_ignored;
    case "a row of source Powo is ignored" powo_row_ignored;
    case "fetched_at is the minimum across rows" fetched_at_is_the_minimum;
    case "fetched_at ignores Failed rows" fetched_at_ignores_failed_rows;
    case
      "plant_refs: a live override, an added link, a soft-deleted one ignored"
      plant_ref_rules;
    case "every derived link classifies to the matching Domain.Link constructor"
      link_classification;
    case "Source_url: every builder classifies back to its link"
      source_url_classification;
    case "toxicity: an en summary gives its first toxic sentence"
      toxicity_en_summary;
    case "toxicity: a disambiguation page gives None and no Wikipedia link"
      toxicity_disambiguation_is_none;
    case "toxicity: a description-only match gives the description"
      toxicity_description_only_match;
    case
      "vernacular: a tie is broken by first position, spelling of the first \
       vote kept, nld dropped"
      vernacular_tie_by_position;
    case "vernacular: more than three groups keep three"
      vernacular_keeps_top_three;
    case "vernacular: groups by vote count descending" vernacular_by_count;
    case
      "origin: present WCVP rows only, deduplicated, by establishment means; \
       red_list: the global IUCN row"
      origin_and_red_list_rules;
    case
      "origin area code: TDWG: prefix kept as code, absent prefix or empty \
       suffix gives None, dedup by code then by name"
      origin_area_code_rules;
    case "filled: family and each range on their own" filled_family_and_ranges;
    case
      "filled: life_form/flowering_months/habitat read a hand-built value; \
       ecology follows habitat.chips, not habitat.phrase"
      filled_life_form_flowering_habitat;
    case
      "rows: the first live row of a source wins, deleted rows do not count, \
       status is not read"
      first_live_row_of_a_source_wins;
    case "every part broken: one problem per part of Payload.all"
      every_part_broken;
    case "a payload that is not an object: one problem per part"
      non_object_payload;
    case "malformed ids and pages give no derived link"
      malformed_ids_give_no_link;
    case "stored plant ref urls are checked against their source"
      stored_urls_are_checked;
    case "toxicity: sentence cuts, negation, accented capitals"
      toxicity_sentences;
    case "Field.all has 14 elements, to_string is distinct"
      field_all_and_to_string;
  ]

(* ---------- the regional layer ---------- *)

let tela_row nn =
  reference_row ~source:Source.Tela ~fetched_at:t_other
    (Payload.tela ~names:None
       ~taxon:(Some (Check.json (Printf.sprintf "tela_taxon_%s.json" nn)))
       ~baseflor:(Some (Check.json (Printf.sprintf "tela_baseflor_%s.json" nn))))

let taxref_row ?protections cd =
  let j part = Some (Check.json (Printf.sprintf "inpn_%s_%s.json" part cd)) in
  let protections =
    match protections with Some p -> Some p | None -> j "protections"
  in
  reference_row ~source:Source.Taxref ~fetched_at:t_other
    (Payload.taxref ~name:(j "name") ~status:(j "status")
       ~red_list:(j "red_list") ~protections)

let protection_t =
  Alcotest.testable Projection.pp_protection Projection.equal_protection

let fr_red_list_t =
  Alcotest.testable Projection.pp_fr_red_list Projection.equal_fr_red_list

let check_sources name expected (sources : Source.t list) =
  Alcotest.(check Testable.yojson)
    name (sources_json expected) (sources_json sources)

let regional_digitalis () =
  let proj =
    project (rows_of digitalis @ [tela_row "22437"; taxref_row "94959"])
  in
  (match proj.fr_status with
  | Some {value; sources} ->
      Alcotest.(check string) "fr_status" "PRESENT" value;
      check_sources "fr_status sources" [Source.Taxref] sources
  | None -> Alcotest.fail "fr_status is None");
  (match proj.fr_protection with
  | Some {value; sources} ->
      Alcotest.check protection_t "fr_protection" Projection.Not_protected value;
      check_sources "fr_protection sources" [Source.Taxref] sources
  | None -> Alcotest.fail "fr_protection is None");
  (match proj.fr_red_list with
  | Some {value; sources = _} ->
      Alcotest.check fr_red_list_t "fr_red_list"
        {category = "LC"; description = Some "Préoccupation mineure"}
        value
  | None -> Alcotest.fail "fr_red_list is None");
  (match proj.flowering_months with
  | Some {value; sources} ->
      Alcotest.(check (list int)) "flowering_months" [5; 6; 7; 8; 9] value;
      check_sources "flowering sources" [Source.Tela] sources
  | None -> Alcotest.fail "flowering_months is None");
  (match proj.habitat with
  | Some {value; sources} ->
      Alcotest.(check (option string))
        "habitat phrase"
        (Some
           "mégaphorbiaies pionnières de clairières acidophiles \
            planitiaires-collinéennes")
        value.phrase;
      Alcotest.(check (list string))
        "habitat chips"
        ["hémihéliophiles"; "mésohydriques"; "acidophiles"; "méso-eutrophiles"]
        value.chips;
      check_sources "habitat sources" [Source.Tela] sources
  | None -> Alcotest.fail "habitat is None");
  (match proj.life_form with
  | Some {value; sources = _} ->
      Alcotest.(check string)
        "life_form" "Hémicryptophytes (>= 1m) bisannuels" value
  | None -> Alcotest.fail "life_form is None");
  Alcotest.(check (list string)) "problems" [] (problem_strings proj.problems);
  Alcotest.(check Testable.yojson)
    "empty_fields: only the global red list"
    (fields_json Projection.Field.[Red_list])
    (fields_json (Projection.empty_fields proj))

let regional_arnica () =
  let proj = project (rows_of arnica @ [tela_row "6646"; taxref_row "83874"]) in
  Alcotest.(check (option string))
    "fr_status" (Some "PRESENT")
    (Option.map (fun (c : _ Projection.cited) -> c.value) proj.fr_status);
  Alcotest.(check (option protection_t))
    "fr_protection: regions then départements, fixture order"
    (Some
       (Projection.Local
          [
            "Centre-Val de Loire";
            "Bourgogne";
            "Aquitaine";
            "Le Cher";
            "Le Lot";
            "L'Isère";
            "La Drôme";
          ]))
    (Option.map (fun (c : _ Projection.cited) -> c.value) proj.fr_protection);
  Alcotest.(check (option string))
    "fr_red_list category" (Some "LC")
    (Option.map
       (fun (c : Projection.fr_red_list Projection.cited) -> c.value.category)
       proj.fr_red_list);
  Alcotest.(check (option (list int)))
    "flowering_months"
    (Some [6; 7])
    (Option.map (fun (c : _ Projection.cited) -> c.value) proj.flowering_months);
  Alcotest.(check (option string))
    "life_form: the principal type, trimmed"
    (Some "Hémicryptophytes (< 1m) rosettés")
    (Option.map (fun (c : _ Projection.cited) -> c.value) proj.life_form);
  Alcotest.(check Testable.yojson)
    "empty_fields: only toxicity"
    (fields_json Projection.Field.[Toxicity])
    (fields_json (Projection.empty_fields proj))

let months_parser () =
  let cases =
    [
      ("5-9", Some [5; 6; 7; 8; 9]);
      ("6", Some [6]);
      ("11-2", Some [1; 2; 11; 12]);
      ("4-6,9", Some [4; 5; 6; 9]);
      (" 4-6 , 5-7 ", Some [4; 5; 6; 7]);
      ("1-12", Some [1; 2; 3; 4; 5; 6; 7; 8; 9; 10; 11; 12]);
      ("", None);
      ("0-3", None);
      ("13", None);
      ("a-b", None);
      ("5-", None);
      ("5-9,x", None);
    ]
  in
  List.iter
    (fun (input, expected) ->
      Alcotest.(check (option (list int)))
        (Printf.sprintf "months %S" input)
        expected (Projection.months input))
    cases

let baseflor_row fields =
  reference_row ~source:Source.Tela ~fetched_at:t_other
    (Payload.tela ~names:None ~taxon:None
       ~baseflor:(Some (`Assoc (("nom_sci", `String "X y") :: fields))))

let habitat_chip_cut () =
  let proj =
    project
      [
        baseflor_row
          [
            ("ve_lumiere.libelle", `String "héliophiles");
            ("ve_humidite_edaph.libelle", `String "mésohydriques (jamais)");
            ("ve_reaction_sol.libelle", `String "mésohydriques (bis)");
            ("ve_nutriments_sol.libelle", `String "  ");
          ];
      ]
  in
  match proj.habitat with
  | Some {value; sources = _} ->
      Alcotest.(check (option string)) "no phrase" None value.phrase;
      Alcotest.(check (list string))
        "a label without \" (\" kept whole; duplicates and blanks dropped"
        ["héliophiles"; "mésohydriques"]
        value.chips
  | None -> Alcotest.fail "habitat is None"

let broken_protections_problem () =
  let proj =
    project (rows_of digitalis @ [taxref_row ~protections:(`String "x") "94959"])
  in
  Alcotest.(check bool)
    "fr_protection is None" true
    (Option.is_none proj.fr_protection);
  Alcotest.(check (option string))
    "fr_status intact" (Some "PRESENT")
    (Option.map (fun (c : _ Projection.cited) -> c.value) proj.fr_status);
  match proj.problems with
  | [{part = Payload.Inpn_protections; error = Decode.Unexpected _}] -> ()
  | ps ->
      Alcotest.failf
        "expected one Inpn_protections Unexpected problem, got [%s]"
        (String.concat "; " (problem_strings ps))

(* Protection pages built from recorded articles: Cypripedium calceolus
   (94041) has a NATIONAL PROTECTION article, Arnica REGIONAL and
   DEPARTMENTAL ones. *)
let articles file =
  match Herbier_net.Json.member "_embedded" (Check.json file) with
  | Some embedded -> Herbier_refs.Decode.list "protectionArticles" embedded
  | None -> Alcotest.failf "%s: no _embedded" file

let protections_page articles =
  `Assoc
    [
      ("_embedded", `Assoc [("protectionArticles", `List articles)]);
      ("page", `Assoc [("totalElements", `Int (List.length articles))]);
    ]

let rec set_overseas (json : Yojson.Safe.t) : Yojson.Safe.t =
  match json with
  | `Assoc kvs ->
      `Assoc
        (List.map
           (fun (k, v) ->
             match k with
             | "overseas" -> (k, `Bool true)
             | _ -> (k, set_overseas v))
           kvs)
  | `List l -> `List (List.map set_overseas l)
  | other -> other

let fr_protection_of page =
  Option.map
    (fun (c : _ Projection.cited) -> c.value)
    (project (rows_of digitalis @ [taxref_row ~protections:page "94959"]))
      .fr_protection

let protection_national () =
  Alcotest.(check (option protection_t))
    "Cypripedium calceolus: National" (Some Projection.National)
    (fr_protection_of (Check.json "inpn_protections_94041.json"))

let protection_national_over_local () =
  Alcotest.(check (option protection_t))
    "a NATIONAL article wins over REGIONAL and DEPARTMENTAL ones"
    (Some Projection.National)
    (fr_protection_of
       (protections_page
          (articles "inpn_protections_83874.json"
          @ articles "inpn_protections_94041.json")))

let protection_overseas_dropped () =
  Alcotest.(check (option protection_t))
    "REGIONAL and DEPARTMENTAL articles located overseas: Not_protected"
    (Some Projection.Not_protected)
    (fr_protection_of
       (protections_page
          (List.map set_overseas (articles "inpn_protections_83874.json"))))

let regional_tests =
  [
    case "Digitalis with the Tela and Taxref rows: the six regional fields"
      regional_digitalis;
    case "Arnica: Local protection places, months 6-7, principal life form"
      regional_arnica;
    case "months: ranges, wrap through December, strict parse" months_parser;
    case "habitat chips: cut before \" (\", blanks and duplicates dropped"
      habitat_chip_cut;
    case "a broken protections part: a problem, fr_protection None, rest intact"
      broken_protections_problem;
    case "protection: a recorded NATIONAL article gives National"
      protection_national;
    case "protection: National wins over Local" protection_national_over_local;
    case "protection: articles located overseas are dropped"
      protection_overseas_dropped;
  ]

(* ---------- « Utilisations » ---------- *)

let uses_digitalis () =
  let proj = project (rows_of digitalis) in
  (match proj.plantuse_uses with
  | Some {value; sources} ->
      Alcotest.(check (list string)) "chips" ["médicinal"] value.summary;
      Alcotest.(check bool) "no line" true (Option.is_none value.text);
      Alcotest.(check string)
        "url" "https://plantuse.plantnet.org/fr/Digitalis_purpurea" value.url;
      check_sources "plantuse sources" [Source.Plantuse] sources
  | None -> Alcotest.fail "plantuse_uses is None");
  match proj.wikipedia_uses with
  | Some {value; sources} ->
      Alcotest.(check string) "section" "Medicinal use" value.section;
      Alcotest.(check string) "lang" "en" value.lang;
      check_sources "wikipedia sources" [Source.Wikipedia] sources
  | None -> Alcotest.fail "wikipedia_uses is None"

let uses_arnica () =
  let proj = project (rows_of arnica) in
  Alcotest.(check bool)
    "plantuse_uses is None (page without box nor prose)" true
    (Option.is_none proj.plantuse_uses);
  match proj.wikipedia_uses with
  | Some {value; _} ->
      Alcotest.(check string) "section" "Phytothérapie" value.section;
      Alcotest.(check string) "lang" "fr" value.lang
  | None -> Alcotest.fail "wikipedia_uses is None"

let uses_neither () =
  let neither =
    {
      digitalis with
      uses = Check.json "wikipedia_extract_fr_Digitalis_purpurea.json";
      plantuse_page = Check.json "plantuse_page_fallopia_japonica.json";
    }
  in
  let proj = project (rows_of neither) in
  Alcotest.(check bool)
    "plantuse_uses None" true
    (Option.is_none proj.plantuse_uses);
  Alcotest.(check bool)
    "wikipedia_uses None" true
    (Option.is_none proj.wikipedia_uses);
  Alcotest.(check (list string)) "problems" [] (problem_strings proj.problems)

let uses_before_plantuse () =
  let rows =
    List.filter_map
      (fun (r : Reference.t) ->
        match r.source with
        | Source.Plantuse -> None
        | Source.Wikipedia ->
            Some
              {
                r with
                payload =
                  Payload.wikipedia ~summary:(Some digitalis.summary_fr)
                    ~uses:None;
              }
        | _ -> Some r)
      (rows_of digitalis)
  in
  let proj = project rows in
  Alcotest.(check bool)
    "plantuse_uses None" true
    (Option.is_none proj.plantuse_uses);
  Alcotest.(check bool)
    "wikipedia_uses None" true
    (Option.is_none proj.wikipedia_uses);
  Alcotest.(check (list string)) "problems" [] (problem_strings proj.problems)

let uses_member_not_an_object () =
  let rows =
    List.map
      (fun (r : Reference.t) ->
        match r.source with
        | Source.Wikipedia ->
            {
              r with
              payload =
                Payload.wikipedia ~summary:(Some digitalis.summary_fr)
                  ~uses:(Some (`String "x"));
            }
        | _ -> r)
      (rows_of digitalis)
  in
  let proj = project rows in
  let reference = project (rows_of digitalis) in
  Alcotest.(check bool)
    "wikipedia_uses None" true
    (Option.is_none proj.wikipedia_uses);
  Alcotest.(check (option string))
    "toxicity (from the summary) intact"
    (Option.map (fun (c : _ Projection.cited) -> c.value) reference.toxicity)
    (Option.map (fun (c : _ Projection.cited) -> c.value) proj.toxicity);
  match proj.problems with
  | [{part = Payload.Wikipedia_uses; _}] -> ()
  | ps ->
      Alcotest.failf "expected one Wikipedia_uses problem, got [%s]"
        (String.concat "; " (problem_strings ps))

(* Digitalis's rows with the GBIF species renamed and another recorded
   Pl@ntUse answer. *)
let with_name_and_page ~scientific ~canonical page_file =
  let species_body =
    match digitalis.species_body with
    | `Assoc fields ->
        `Assoc
          (("scientificName", `String scientific)
          :: ("canonicalName", `String canonical)
          :: List.filter
               (fun (k, _) -> k <> "scientificName" && k <> "canonicalName")
               fields)
    | other -> other
  in
  {digitalis with species_body; plantuse_page = Check.json page_file}

let plantuse_title proj =
  Option.map
    (fun (c : Projection.Uses.plantuse Projection.cited) -> c.value.title)
    proj.Projection.plantuse_uses

let uses_redirect () =
  let proj =
    project
      (rows_of
         (with_name_and_page ~scientific:"Polygonum cuspidatum Siebold & Zucc."
            ~canonical:"Polygonum cuspidatum"
            "plantuse_page_polygonum_cuspidatum.json"))
  in
  Alcotest.(check (option string))
    "the redirect's target" (Some "Reynoutria japonica") (plantuse_title proj)

let uses_subspecies () =
  let proj =
    project
      (rows_of
         (with_name_and_page ~scientific:"Digitalis purpurea subsp. purpurea"
            ~canonical:"Digitalis purpurea purpurea"
            "plantuse_page_digitalis_purpurea_subsp_purpurea.json"))
  in
  Alcotest.(check (option string))
    "the binomial's page" (Some "Digitalis purpurea") (plantuse_title proj)

let uses_no_taxon () =
  let rows =
    List.filter
      (fun (r : Reference.t) -> r.source <> Source.Gbif)
      (rows_of digitalis)
  in
  Alcotest.(check (option string))
    "no name, no Pl@ntUse page" None
    (plantuse_title (project rows))

let uses_tests =
  [
    case "a redirected name: the Pl@ntUse page it leads to" uses_redirect;
    case "a subspecies without its own page: the binomial's" uses_subspecies;
    case "no GBIF species: no Pl@ntUse part" uses_no_taxon;
    case "Digitalis: Pl@ntUse « médicinal » and the en « Medicinal use »"
      uses_digitalis;
    case "Arnica: no Pl@ntUse part, the fr « Phytothérapie » paragraph"
      uses_arnica;
    case "neither source has uses data: both None, no problem" uses_neither;
    case "a plant fetched before Pl@ntUse was a source: both None, no problem"
      uses_before_plantuse;
    case "a uses member that is not an object: one problem, summary intact"
      uses_member_not_an_object;
  ]

let suite =
  ( "projection",
    digitalis_tests @ arnica_tests @ rules_tests @ regional_tests @ uses_tests
  )
