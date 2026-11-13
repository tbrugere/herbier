module Decode = Herbier_refs.Decode
module Qid = Herbier_refs.Qid
module Payload = Herbier_refs.Payload
module Gbif = Herbier_refs.Sources.Gbif
module Wikidata = Herbier_refs.Sources.Wikidata
module Wikipedia = Herbier_refs.Sources.Wikipedia
module Source = Herbier_domain.Reference.Source
module Testable = Herbier_test_support.Testable

(* ---------- fixtures ---------- *)

let species_digitalis = Check.json "gbif_species_5414995.json"
let species_arnica = Check.json "gbif_species_5405976.json"
let vernacular_names_digitalis = Check.json "gbif_vernacular_names_5414995.json"
let vernacular_names_arnica = Check.json "gbif_vernacular_names_5405976.json"
let distributions_digitalis = Check.json "gbif_distributions_5414995.json"
let distributions_arnica = Check.json "gbif_distributions_5405976.json"
let occurrence_count_digitalis = Check.json "gbif_occurrence_count_5414995.json"
let occurrence_count_arnica = Check.json "gbif_occurrence_count_5405976.json"
let plantnet_media_digitalis = Check.json "gbif_plantnet_media_5414995.json"
let plantnet_media_arnica = Check.json "gbif_plantnet_media_5405976.json"
let search_p846_digitalis = Check.json "wikidata_search_p846_5414995.json"
let search_p846_arnica = Check.json "wikidata_search_p846_5405976.json"
let entity_digitalis = Check.json "wikidata_entity_Q157555.json"
let entity_arnica = Check.json "wikidata_entity_Q207848.json"
let entity_q0 = Check.json "wikidata_entity_Q0.json"

let summary_fr_digitalis =
  Check.json "wikipedia_summary_fr_Digitalis_purpurea.json"

let summary_fr_arnica = Check.json "wikipedia_summary_fr_Arnica_montana.json"

let summary_en_digitalis =
  Check.json "wikipedia_summary_en_Digitalis_purpurea.json"

let summary_fr_lis = Check.json "wikipedia_summary_fr_Lis.json"

(* ---------- testables ---------- *)

let qid_t = Alcotest.testable Qid.pp Qid.equal
let taxon_t = Alcotest.testable Gbif.Taxon.pp Gbif.Taxon.equal
let vernacular_t = Alcotest.testable Gbif.Vernacular.pp Gbif.Vernacular.equal

let distribution_t =
  Alcotest.testable Gbif.Distribution.pp Gbif.Distribution.equal

let image_t = Alcotest.testable Gbif.Image.pp Gbif.Image.equal
let entity_t = Alcotest.testable Wikidata.Entity.pp Wikidata.Entity.equal
let summary_t = Alcotest.testable Wikipedia.pp Wikipedia.equal

let page_t t =
  Alcotest.testable
    (Gbif.pp_page (Alcotest.pp t))
    (Gbif.equal_page (Alcotest.equal t))

(* [decode (prune p b) = decode p b], one [Alcotest.check] per part, through
   that part's decoder. *)
let check_prune_preserves_decoding name (part : Payload.part) body =
  let same value decode =
    Alcotest.(check (result value Check.error))
      name (decode body)
      (decode (Payload.prune part body))
  in
  match part with
  | Gbif_species -> same taxon_t Gbif.species_of_json
  | Gbif_vernacular_names ->
      same (page_t vernacular_t) Gbif.vernacular_names_of_json
  | Gbif_distributions ->
      same (page_t distribution_t) Gbif.distributions_of_json
  | Gbif_occurrence_count -> same Alcotest.int Gbif.occurrence_count_of_json
  | Plantnet_media -> same (page_t image_t) Gbif.plantnet_media_of_json
  | Wikidata_search -> same (Alcotest.list qid_t) Wikidata.search_of_json
  | Wikidata_entity -> same (Alcotest.option entity_t) Wikidata.entity_of_json
  | Wikipedia_summary -> same summary_t Wikipedia.summary_of_json

(* ---------- all, source, name, parts ---------- *)

let tables_tests =
  [
    ( "all has 8 parts, declaration order",
      `Quick,
      fun () ->
        Alcotest.(check (list string))
          "all"
          [
            "Gbif_species";
            "Gbif_vernacular_names";
            "Gbif_distributions";
            "Gbif_occurrence_count";
            "Plantnet_media";
            "Wikidata_search";
            "Wikidata_entity";
            "Wikipedia_summary";
          ]
          (List.map
             (function
               | Payload.Gbif_species -> "Gbif_species"
               | Payload.Gbif_vernacular_names -> "Gbif_vernacular_names"
               | Payload.Gbif_distributions -> "Gbif_distributions"
               | Payload.Gbif_occurrence_count -> "Gbif_occurrence_count"
               | Payload.Plantnet_media -> "Plantnet_media"
               | Payload.Wikidata_search -> "Wikidata_search"
               | Payload.Wikidata_entity -> "Wikidata_entity"
               | Payload.Wikipedia_summary -> "Wikipedia_summary")
             Payload.all) );
    ( "source: the four Gbif_* parts and occurrence_count are Gbif, \
       Plantnet_media is Plantnet, both Wikidata_* are Wikidata, \
       Wikipedia_summary is Wikipedia",
      `Quick,
      fun () ->
        let source_name s = Source.to_string s in
        Alcotest.(check (list string))
          "sources, in all order"
          [
            "gbif";
            "gbif";
            "gbif";
            "gbif";
            "plantnet";
            "wikidata";
            "wikidata";
            "wikipedia";
          ]
          (List.map (fun p -> source_name (Payload.source p)) Payload.all) );
    ( "name: the member name of each part",
      `Quick,
      fun () ->
        Alcotest.(check (list string))
          "names"
          [
            "species";
            "vernacular_names";
            "distributions";
            "occurrence_count";
            "media";
            "search";
            "entity";
            "summary";
          ]
          (List.map Payload.name Payload.all) );
    ( "parts of an unfetched source (powo, ipni, taxref, tela, eppo, inat) is []",
      `Quick,
      fun () ->
        List.iter
          (fun s ->
            Alcotest.(check int)
              (Source.to_string s ^ ": parts is []")
              0
              (List.length (Payload.parts s)))
          [
            Source.Powo;
            Source.Ipni;
            Source.Taxref;
            Source.Tela;
            Source.Eppo;
            Source.Inat;
          ] );
    ( "parts of a fetched source, in all order",
      `Quick,
      fun () ->
        let names s = List.map Payload.name (Payload.parts s) in
        Alcotest.(check (list string))
          "gbif"
          ["species"; "vernacular_names"; "distributions"; "occurrence_count"]
          (names Source.Gbif);
        Alcotest.(check (list string))
          "plantnet" ["media"] (names Source.Plantnet);
        Alcotest.(check (list string))
          "wikidata" ["search"; "entity"] (names Source.Wikidata);
        Alcotest.(check (list string))
          "wikipedia" ["summary"] (names Source.Wikipedia) );
    ( "every part is in (parts (source part))",
      `Quick,
      fun () ->
        List.iter
          (fun p ->
            Alcotest.(check bool)
              (Payload.name p ^ " is in parts (source p)")
              true
              (List.exists
                 (fun p' -> String.equal (Payload.name p') (Payload.name p))
                 (Payload.parts (Payload.source p))))
          Payload.all );
  ]

(* ---------- prune preserves decoding, on the recorded fixtures ---------- *)

let fixture_prune_tests =
  let case name part body =
    (name, `Quick, fun () -> check_prune_preserves_decoding name part body)
  in
  [
    case "species Digitalis" Payload.Gbif_species species_digitalis;
    case "species Arnica" Payload.Gbif_species species_arnica;
    case "vernacular_names Digitalis" Payload.Gbif_vernacular_names
      vernacular_names_digitalis;
    case "vernacular_names Arnica" Payload.Gbif_vernacular_names
      vernacular_names_arnica;
    case "distributions Digitalis" Payload.Gbif_distributions
      distributions_digitalis;
    case "distributions Arnica" Payload.Gbif_distributions distributions_arnica;
    case "occurrence_count Digitalis" Payload.Gbif_occurrence_count
      occurrence_count_digitalis;
    case "occurrence_count Arnica" Payload.Gbif_occurrence_count
      occurrence_count_arnica;
    case "plantnet_media Digitalis" Payload.Plantnet_media
      plantnet_media_digitalis;
    case "plantnet_media Arnica" Payload.Plantnet_media plantnet_media_arnica;
    case "wikidata search Digitalis" Payload.Wikidata_search
      search_p846_digitalis;
    case "wikidata search Arnica" Payload.Wikidata_search search_p846_arnica;
    case "wikidata entity Digitalis (Q157555)" Payload.Wikidata_entity
      entity_digitalis;
    case "wikidata entity Arnica (Q207848)" Payload.Wikidata_entity
      entity_arnica;
    case "wikidata entity Q0 (no such entity)" Payload.Wikidata_entity entity_q0;
    case "wikipedia summary fr Digitalis" Payload.Wikipedia_summary
      summary_fr_digitalis;
    case "wikipedia summary fr Arnica" Payload.Wikipedia_summary
      summary_fr_arnica;
    case "wikipedia summary en Digitalis" Payload.Wikipedia_summary
      summary_en_digitalis;
    case "wikipedia summary fr Lis (disambiguation)" Payload.Wikipedia_summary
      summary_fr_lis;
  ]

(* ---------- prune preserves decoding, on malformed literals ---------- *)

let occurrence_without_key =
  `Assoc
    [
      ( "results",
        `List
          [
            `Assoc
              [
                ( "media",
                  `List
                    [
                      `Assoc
                        [
                          ("type", `String "StillImage");
                          ("identifier", `String "https://x/img.jpg");
                          ("license", `String "A (cc-by)");
                        ];
                    ] );
              ];
          ] );
      ("endOfRecords", `Bool true);
    ]

let malformed_literals =
  [
    ("null", `Null);
    ("an empty array (for a page part)", `List []);
    ("results is an int, not an array", `Assoc [("results", `Int 3)]);
    ( "a results element that is a string",
      `Assoc [("results", `List [`String "x"]); ("endOfRecords", `Bool true)] );
    ("an occurrence without a key", occurrence_without_key);
    ("entities is an array, not an object", `Assoc [("entities", `List [])]);
    ( "a root error object",
      `Assoc [("error", `Assoc [("code", `String "x"); ("info", `String "y")])]
    );
  ]

let malformed_prune_tests =
  List.concat_map
    (fun (what, body) ->
      List.map
        (fun part ->
          ( Printf.sprintf "%s: %s" (Payload.name part) what,
            `Quick,
            fun () ->
              check_prune_preserves_decoding
                (Printf.sprintf "%s on %s" (Payload.name part) what)
                part body ))
        Payload.all)
    malformed_literals

(* ---------- prune actually prunes ---------- *)

let entity_fields pruned =
  match pruned with
  | `Assoc kvs -> (
      match List.assoc_opt "entities" kvs with
      | Some (`Assoc [(_, `Assoc fields)]) -> fields
      | Some other ->
          Alcotest.failf "entities: %s" (Yojson.Safe.to_string other)
      | None -> Alcotest.fail "no entities member")
  | other ->
      Alcotest.failf "root not an object: %s" (Yojson.Safe.to_string other)

let sorted_keys = function
  | `Assoc kvs -> List.sort String.compare (List.map fst kvs)
  | other -> Alcotest.failf "not an object: %s" (Yojson.Safe.to_string other)

(* The documented keys present before pruning are exactly the keys after. *)
let check_kept what documented raw pruned =
  Alcotest.(check (list string))
    what
    (List.filter (fun k -> List.mem k documented) (sorted_keys raw))
    (sorted_keys pruned)

let array_member key = function
  | `Assoc kvs -> (
      match List.assoc_opt key kvs with
      | Some (`List l) -> l
      | _ -> Alcotest.failf "%s missing or not an array" key)
  | other -> Alcotest.failf "not an object: %s" (Yojson.Safe.to_string other)

let check_items what check raws pruneds =
  Alcotest.(check int)
    (what ^ " count") (List.length raws) (List.length pruneds);
  List.iter2 check raws pruneds

let check_page part ~result raw =
  let pruned = Payload.prune part raw in
  Alcotest.(check bool)
    "the fixture has keys to drop" true
    (sorted_keys raw <> sorted_keys pruned);
  check_kept "root keys" ["results"; "endOfRecords"; "count"] raw pruned;
  check_items "results" result
    (array_member "results" raw)
    (array_member "results" pruned)

let prune_keys_tests =
  [
    ( "prune Gbif_vernacular_names keeps the documented root and result keys",
      `Quick,
      fun () ->
        check_page Payload.Gbif_vernacular_names
          ~result:
            (check_kept "result keys"
               ["vernacularName"; "language"; "source"; "country"])
          vernacular_names_digitalis );
    ( "prune Gbif_distributions keeps the documented root and result keys",
      `Quick,
      fun () ->
        check_page Payload.Gbif_distributions
          ~result:
            (check_kept "result keys"
               [
                 "locationId";
                 "locality";
                 "country";
                 "status";
                 "establishmentMeans";
                 "threatStatus";
                 "source";
               ])
          distributions_digitalis );
    ( "prune Plantnet_media keeps the documented root, result and media keys",
      `Quick,
      fun () ->
        check_page Payload.Plantnet_media
          ~result:(fun raw pruned ->
            check_kept "result keys" ["key"; "references"; "media"] raw pruned;
            check_items "media"
              (check_kept "media keys"
                 [
                   "type";
                   "identifier";
                   "title";
                   "license";
                   "rightsHolder";
                   "creator";
                   "source";
                 ])
              (array_member "media" raw)
              (array_member "media" pruned))
          plantnet_media_digitalis );
  ]

let prune_prunes_tests =
  [
    ( "prune Wikidata_entity drops labels, descriptions and aliases",
      `Quick,
      fun () ->
        let fields =
          entity_fields (Payload.prune Payload.Wikidata_entity entity_digitalis)
        in
        List.iter
          (fun k ->
            Alcotest.(check bool)
              (k ^ " is absent") false (List.mem_assoc k fields))
          ["labels"; "descriptions"; "aliases"] );
    ( "prune Wikidata_entity drops claim P31, keeps the listed properties \
       reduced to rank and mainsnak",
      `Quick,
      fun () ->
        let fields =
          entity_fields (Payload.prune Payload.Wikidata_entity entity_digitalis)
        in
        match List.assoc_opt "claims" fields with
        | Some (`Assoc claims) -> (
            Alcotest.(check bool)
              "P31 is absent" false
              (List.mem_assoc "P31" claims);
            match List.assoc_opt "P846" claims with
            | Some (`List (`Assoc stmt :: _)) ->
                Alcotest.(check (list string))
                  "a P846 statement's keys" ["mainsnak"; "rank"]
                  (List.sort String.compare (List.map fst stmt))
            | _ -> Alcotest.fail "P846 claim missing or not a non-empty list")
        | _ -> Alcotest.fail "claims missing or not an object" );
    ( "prune Wikidata_entity keeps sitelinks only among fr/en/de/it",
      `Quick,
      fun () ->
        let fields =
          entity_fields (Payload.prune Payload.Wikidata_entity entity_digitalis)
        in
        match List.assoc_opt "sitelinks" fields with
        | Some (`Assoc sitelinks) ->
            Alcotest.(check (list string))
              "sitelinks keys"
              ["dewiki"; "enwiki"; "frwiki"; "itwiki"]
              (List.sort String.compare (List.map fst sitelinks))
        | _ -> Alcotest.fail "sitelinks missing or not an object" );
    ( "prune Plantnet_media result objects have only keys among key, \
       references, media",
      `Quick,
      fun () ->
        match Payload.prune Payload.Plantnet_media plantnet_media_digitalis with
        | `Assoc kvs -> (
            match List.assoc_opt "results" kvs with
            | Some (`List results) ->
                Alcotest.(check bool)
                  "at least one result" true
                  (List.length results > 0);
                List.iter
                  (fun result ->
                    match result with
                    | `Assoc fields ->
                        List.iter
                          (fun (k, _) ->
                            Alcotest.(check bool)
                              (k ^ " is one of key, references, media")
                              true
                              (List.mem k ["key"; "references"; "media"]))
                          fields
                    | other ->
                        Alcotest.failf "result not an object: %s"
                          (Yojson.Safe.to_string other))
                  results
            | _ -> Alcotest.fail "results missing or not an array")
        | other ->
            Alcotest.failf "root not an object: %s"
              (Yojson.Safe.to_string other) );
  ]

(* ---------- size ---------- *)

let payload_size what payloads =
  let total =
    List.fold_left
      (fun acc p -> acc + String.length (Yojson.Safe.to_string p))
      0 payloads
  in
  Alcotest.(check bool)
    (Printf.sprintf "%s: total payload size %d < 131072" what total)
    true (total < 131_072)

let size_tests =
  [
    ( "Digitalis purpurea: the four payloads together are under 131072 bytes",
      `Quick,
      fun () ->
        payload_size "Digitalis"
          [
            Payload.gbif ~species:(Some species_digitalis)
              ~vernacular_names:(Some vernacular_names_digitalis)
              ~distributions:(Some distributions_digitalis)
              ~occurrence_count:(Some occurrence_count_digitalis);
            Payload.plantnet ~media:(Some plantnet_media_digitalis);
            Payload.wikidata ~search:(Some search_p846_digitalis)
              ~entity:(Some entity_digitalis);
            Payload.wikipedia ~summary:(Some summary_fr_digitalis);
          ] );
    ( "Arnica montana: the four payloads together are under 131072 bytes",
      `Quick,
      fun () ->
        payload_size "Arnica"
          [
            Payload.gbif ~species:(Some species_arnica)
              ~vernacular_names:(Some vernacular_names_arnica)
              ~distributions:(Some distributions_arnica)
              ~occurrence_count:(Some occurrence_count_arnica);
            Payload.plantnet ~media:(Some plantnet_media_arnica);
            Payload.wikidata ~search:(Some search_p846_arnica)
              ~entity:(Some entity_arnica);
            Payload.wikipedia ~summary:(Some summary_fr_arnica);
          ] );
  ]

(* ---------- builders ---------- *)

let keys_of = function
  | `Assoc kvs -> List.map fst kvs
  | other -> Alcotest.failf "not an object: %s" (Yojson.Safe.to_string other)

let small = `Assoc [("x", `Int 1)]

let builder_tests =
  [
    ( "gbif: member order is all order, whichever parts are given",
      `Quick,
      fun () ->
        Alcotest.(check (list string))
          "every part given"
          ["species"; "vernacular_names"; "distributions"; "occurrence_count"]
          (keys_of
             (Payload.gbif ~occurrence_count:(Some small) ~species:(Some small)
                ~distributions:(Some small) ~vernacular_names:(Some small)));
        Alcotest.(check (list string))
          "only some parts given, order kept"
          ["vernacular_names"; "occurrence_count"]
          (keys_of
             (Payload.gbif ~occurrence_count:(Some small) ~species:None
                ~distributions:None ~vernacular_names:(Some small))) );
    ( "gbif: all None gives Assoc []",
      `Quick,
      fun () ->
        Alcotest.(check Testable.yojson)
          "empty" (`Assoc [])
          (Payload.gbif ~species:None ~vernacular_names:None ~distributions:None
             ~occurrence_count:None) );
    ( "plantnet: one member when given, Assoc [] when None",
      `Quick,
      fun () ->
        Alcotest.(check (list string))
          "media given" ["media"]
          (keys_of (Payload.plantnet ~media:(Some small)));
        Alcotest.(check Testable.yojson)
          "media absent" (`Assoc [])
          (Payload.plantnet ~media:None) );
    ( "wikidata: member order is search then entity",
      `Quick,
      fun () ->
        Alcotest.(check (list string))
          "both given" ["search"; "entity"]
          (keys_of (Payload.wikidata ~search:(Some small) ~entity:(Some small)));
        Alcotest.(check (list string))
          "only entity given" ["entity"]
          (keys_of (Payload.wikidata ~search:None ~entity:(Some small)));
        Alcotest.(check Testable.yojson)
          "both absent" (`Assoc [])
          (Payload.wikidata ~search:None ~entity:None) );
    ( "wikipedia: one member when given, Assoc [] when None",
      `Quick,
      fun () ->
        Alcotest.(check (list string))
          "summary given" ["summary"]
          (keys_of (Payload.wikipedia ~summary:(Some small)));
        Alcotest.(check Testable.yojson)
          "summary absent" (`Assoc [])
          (Payload.wikipedia ~summary:None) );
  ]

(* ---------- get ---------- *)

let get_tests =
  [
    ( "get finds the member named after the part",
      `Quick,
      fun () ->
        (* Wikipedia_summary is identity-pruned (small), so the stored member
           is exactly [small], not reshaped by the builder. *)
        let payload = Payload.wikipedia ~summary:(Some small) in
        Alcotest.(check (option Testable.yojson))
          "summary present" (Some small)
          (Payload.get Payload.Wikipedia_summary payload) );
    ( "get is None when the member is absent",
      `Quick,
      fun () ->
        let payload = Payload.plantnet ~media:None in
        Alcotest.(check (option Testable.yojson))
          "media absent" None
          (Payload.get Payload.Plantnet_media payload) );
    ( "get is None when the member is JSON null",
      `Quick,
      fun () ->
        Alcotest.(check (option Testable.yojson))
          "null member" None
          (Payload.get Payload.Plantnet_media (`Assoc [("media", `Null)])) );
    ( "get is None when the payload is not an object",
      `Quick,
      fun () ->
        Alcotest.(check (option Testable.yojson))
          "a list" None
          (Payload.get Payload.Plantnet_media (`List []));
        Alcotest.(check (option Testable.yojson))
          "null" None
          (Payload.get Payload.Plantnet_media `Null) );
  ]

let suite =
  ( "payload",
    tables_tests
    @ fixture_prune_tests
    @ malformed_prune_tests
    @ prune_prunes_tests
    @ prune_keys_tests
    @ size_tests
    @ builder_tests
    @ get_tests )
