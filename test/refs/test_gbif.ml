module Decode = Herbier_refs.Decode
module Gbif = Herbier_refs.Sources.Gbif
module Organ = Herbier_domain.Reference.Organ
module Testable = Herbier_test_support.Testable
module Text = Herbier_test_support.Text

let check_unexpected_path name expected_path = function
  | Error (Decode.Unexpected {path; _}) ->
      Alcotest.(check string) name expected_path path
  | Error e ->
      Alcotest.failf "%s: expected Unexpected, got %s" name
        (Decode.error_to_string e)
  | Ok _ -> Alcotest.failf "%s: expected Error, got Ok" name

let check_is_error name = function
  | Error _ -> ()
  | Ok _ -> Alcotest.failf "%s: expected Error, got Ok" name

let str s = `String s
let int n = `Int n
let bool b = `Bool b

(* ---------- testables ---------- *)

let status_t = Alcotest.testable Gbif.Status.pp Gbif.Status.equal
let taxon_t = Alcotest.testable Gbif.Taxon.pp Gbif.Taxon.equal
let match_t = Alcotest.testable Gbif.pp_match_ Gbif.equal_match_
let vernacular_t = Alcotest.testable Gbif.Vernacular.pp Gbif.Vernacular.equal
let organ_t = Alcotest.testable Organ.pp Organ.equal

let page_t t =
  Alcotest.testable
    (Gbif.pp_page (Alcotest.pp t))
    (Gbif.equal_page (Alcotest.equal t))

(* ---------- fixtures ---------- *)

let digitalis_species = Check.json "gbif_species_5414995.json"
let arnica_species = Check.json "gbif_species_5405976.json"
let fallopia_species = Check.json "gbif_species_5334357.json"
let match_digitalis_l = Check.json "gbif_match_digitalis_purpurea_l.json"
let match_digitalis_fuzzy = Check.json "gbif_match_digitalis_purpurae.json"
let match_fallopia = Check.json "gbif_match_fallopia_japonica.json"
let match_xyzzy = Check.json "gbif_match_xyzzy_foo.json"
let match_none = Check.json "gbif_match_none_zzzzqqq.json"
let suggest_digitalis = Check.json "gbif_suggest_digitalis_purp.json"

let vernacular_search_digitale =
  Check.json "gbif_vernacular_search_digitale_pourpre.json"

let vernacular_names_digitalis = Check.json "gbif_vernacular_names_5414995.json"
let vernacular_names_arnica = Check.json "gbif_vernacular_names_5405976.json"
let distributions_digitalis = Check.json "gbif_distributions_5414995.json"
let distributions_arnica = Check.json "gbif_distributions_5405976.json"
let occurrence_count_digitalis = Check.json "gbif_occurrence_count_5414995.json"
let occurrence_count_arnica = Check.json "gbif_occurrence_count_5405976.json"
let plantnet_media_digitalis = Check.json "gbif_plantnet_media_5414995.json"
let plantnet_media_arnica = Check.json "gbif_plantnet_media_5405976.json"

let gbif_page results =
  `Assoc [("results", `List results); ("endOfRecords", `Bool true)]

let status_of j =
  match Gbif.species_of_json j with
  | Ok (t : Gbif.Taxon.t) -> t.status
  | Error e -> Alcotest.failf "decode failed: %s" (Decode.error_to_string e)

let species_with_status s =
  `Assoc
    [
      ("key", `Int 1);
      ("scientificName", `String "Foo bar L.");
      ("taxonomicStatus", `String s);
    ]

(* ---------- species_of_json ---------- *)

let species_tests =
  [
    ( "Digitalis purpurea: every field",
      `Quick,
      fun () ->
        Check.check_result "species" taxon_t
          (Ok
             {
               Gbif.Taxon.key = 5414995;
               scientific_name = "Digitalis purpurea L.";
               canonical_name = Some "Digitalis purpurea";
               authorship = Some "L.";
               rank = Some "SPECIES";
               status = Some Accepted;
               accepted_key = None;
               family = Some "Plantaginaceae";
               vernacular_name = Some "Foxglove";
             })
          (Gbif.species_of_json digitalis_species) );
    ( "Arnica montana: scientific name, family, status",
      `Quick,
      fun () ->
        match Gbif.species_of_json arnica_species with
        | Ok t ->
            Alcotest.(check string)
              "scientific_name" "Arnica montana L." t.scientific_name;
            Alcotest.(check (option string))
              "family" (Some "Asteraceae") t.family;
            Alcotest.(check (option status_t))
              "status" (Some Gbif.Status.Accepted) t.status
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "Fallopia japonica: synonym with an accepted key",
      `Quick,
      fun () ->
        match Gbif.species_of_json fallopia_species with
        | Ok t ->
            Alcotest.(check (option status_t))
              "status" (Some Gbif.Status.Synonym) t.status;
            Alcotest.(check (option int))
              "accepted_key" (Some 2889173) t.accepted_key
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "missing key is Unexpected at /key",
      `Quick,
      fun () ->
        check_unexpected_path "path" "/key" (Gbif.species_of_json (`Assoc []))
    );
    ( "a non-object root is Unexpected at the root",
      `Quick,
      fun () ->
        check_unexpected_path "path" "" (Gbif.species_of_json (`List [])) );
    ( "a blank authorship (GBIF sends \"\") is None",
      `Quick,
      fun () ->
        let j =
          `Assoc
            [
              ("key", `Int 1);
              ("scientificName", `String "Foo bar L.");
              ("authorship", `String "");
            ]
        in
        match Gbif.species_of_json j with
        | Ok t ->
            Alcotest.(check (option string)) "authorship" None t.authorship
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
  ]

let status_tests =
  let case name raw expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.(check (option status_t))
          "status" (Some expected)
          (status_of (species_with_status raw)) )
  in
  [
    case "DOUBTFUL is Doubtful" "DOUBTFUL" Doubtful;
    case "HETEROTYPIC_SYNONYM is Synonym" "HETEROTYPIC_SYNONYM" Synonym;
    case "PROPARTE_SYNONYM is Synonym" "PROPARTE_SYNONYM" Synonym;
    case "an unknown status is Other, as given" "MISAPPLIED"
      (Other "MISAPPLIED");
    ( "a missing taxonomicStatus is None",
      `Quick,
      fun () ->
        Alcotest.(check (option status_t))
          "status" None
          (status_of
             (`Assoc [("key", `Int 1); ("scientificName", `String "Foo bar")]))
    );
  ]

(* ---------- match_of_json ---------- *)

let match_tests =
  [
    ( "exact match: fuzzy false, confidence 100",
      `Quick,
      fun () ->
        match Gbif.match_of_json match_digitalis_l with
        | Ok (Matched {taxon; fuzzy; confidence}) ->
            Alcotest.(check int) "key" 5414995 taxon.key;
            Alcotest.(check bool) "fuzzy" false fuzzy;
            Alcotest.(check (option int)) "confidence" (Some 100) confidence
        | Ok _ -> Alcotest.fail "expected Matched"
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "fuzzy match: fuzzy true, same key",
      `Quick,
      fun () ->
        match Gbif.match_of_json match_digitalis_fuzzy with
        | Ok (Matched {taxon; fuzzy; _}) ->
            Alcotest.(check int) "key" 5414995 taxon.key;
            Alcotest.(check bool) "fuzzy" true fuzzy
        | Ok _ -> Alcotest.fail "expected Matched"
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "exact match on a synonym carries its accepted key",
      `Quick,
      fun () ->
        match Gbif.match_of_json match_fallopia with
        | Ok (Matched {taxon; _}) ->
            Alcotest.(check int) "key" 5334357 taxon.key;
            Alcotest.(check (option status_t))
              "status" (Some Gbif.Status.Synonym) taxon.status;
            Alcotest.(check (option int))
              "accepted_key" (Some 2889173) taxon.accepted_key
        | Ok _ -> Alcotest.fail "expected Matched"
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "nonsense input under kingdom=Plantae matches only the kingdom",
      `Quick,
      fun () ->
        match Gbif.match_of_json match_xyzzy with
        | Ok (Higher_rank t) ->
            Alcotest.(check int) "key" 6 t.key;
            Alcotest.(check (option string)) "rank" (Some "KINGDOM") t.rank
        | Ok _ -> Alcotest.fail "expected Higher_rank"
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "no kingdom filter and no hit at all is No_match",
      `Quick,
      fun () ->
        Check.check_result "match" match_t (Ok No_match)
          (Gbif.match_of_json match_none) );
    ( "an EXACT match without usageKey is Unexpected at /usageKey",
      `Quick,
      fun () ->
        check_unexpected_path "path" "/usageKey"
          (Gbif.match_of_json
             (`Assoc
                [
                  ("matchType", `String "EXACT");
                  ("scientificName", `String "Foo bar");
                ])) );
    ( "a missing matchType is Unexpected at /matchType",
      `Quick,
      fun () ->
        check_unexpected_path "path" "/matchType"
          (Gbif.match_of_json (`Assoc [])) );
    ( "an unknown matchType is Unexpected at /matchType",
      `Quick,
      fun () ->
        check_unexpected_path "path" "/matchType"
          (Gbif.match_of_json (`Assoc [("matchType", `String "VARIANT")])) );
  ]

(* ---------- suggest_of_json ---------- *)

let suggest_tests =
  [
    ( "first result, length, every rank is SPECIES",
      `Quick,
      fun () ->
        match Gbif.suggest_of_json suggest_digitalis with
        | Ok taxa ->
            Alcotest.(check int) "length" 6 (List.length taxa);
            (match taxa with
            | first :: _ -> Alcotest.(check int) "first key" 5414995 first.key
            | [] -> Alcotest.fail "empty");
            List.iter
              (fun (t : Gbif.Taxon.t) ->
                Alcotest.(check (option string)) "rank" (Some "SPECIES") t.rank)
              taxa
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "authorship is what scientificName adds to canonicalName",
      `Quick,
      fun () ->
        match Gbif.suggest_of_json suggest_digitalis with
        | Ok taxa ->
            Alcotest.(check (list (pair int (option string))))
              "authorships"
              [
                (5414995, Some "L.");
                (7549341, Some "Lindl.");
                (8296187, Some "G.Mey.");
                (7971454, Some "Lej.");
                (7354417, Some "Roth");
                (8192969, Some "H.L\u{00E9}v., 1917");
              ]
              (List.map (fun (t : Gbif.Taxon.t) -> (t.key, t.authorship)) taxa)
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "a rank marker is skipped; words that differ give no authorship",
      `Quick,
      fun () ->
        let taxon name canonical =
          `Assoc
            [
              ("key", `Int 1);
              ("scientificName", `String name);
              ("canonicalName", `String canonical);
            ]
        in
        match
          Gbif.suggest_of_json
            (`List
               [
                 taxon "Digitalis purpurea subsp. purpurea"
                   "Digitalis purpurea purpurea";
                 taxon "Digitalis lutea Lam." "Digitalis grandiflora";
               ])
        with
        | Ok taxa ->
            Alcotest.(check (list (option string)))
              "authorships" [None; None]
              (List.map (fun (t : Gbif.Taxon.t) -> t.authorship) taxa)
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "a non-array root is Unexpected at the root",
      `Quick,
      fun () ->
        check_unexpected_path "path" "" (Gbif.suggest_of_json (`Assoc [])) );
    ( "an element missing its required key is dropped, the rest kept",
      `Quick,
      fun () ->
        let j =
          `List
            [
              `Assoc [("key", `Int 1); ("scientificName", `String "A")];
              `Assoc [("scientificName", `String "B")];
              `Assoc [("key", `Int 3); ("scientificName", `String "C")];
            ]
        in
        match Gbif.suggest_of_json j with
        | Ok taxa ->
            Alcotest.(check (list int))
              "keys" [1; 3]
              (List.map (fun (t : Gbif.Taxon.t) -> t.key) taxa)
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
  ]

(* ---------- vernacular_search_of_json ---------- *)

let vernacular_search_tests =
  [
    ( "results non-empty, count as recorded, a fra name for key 5414995",
      `Quick,
      fun () ->
        match Gbif.vernacular_search_of_json vernacular_search_digitale with
        | Ok page -> (
            Alcotest.(check bool) "non-empty" true (List.length page.results > 0);
            Alcotest.(check (option int)) "count" (Some 3) page.count;
            let found =
              List.find_opt
                (fun ((t : Gbif.Taxon.t), _) -> t.key = 5414995)
                page.results
            in
            match found with
            | None -> Alcotest.fail "key 5414995 not found in results"
            | Some (_, vernaculars) ->
                let has_digitale_pourpre =
                  List.exists
                    (fun (v : Gbif.Vernacular.t) ->
                      match v.language with
                      | Some "fra" ->
                          Text.contains ~sub:"Digitale pourpre" v.name
                      | _ -> false)
                    vernaculars
                in
                Alcotest.(check bool)
                  "fra name mentions Digitale pourpre" true has_digitale_pourpre
            )
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
  ]

let vernacular_search_inline_tests =
  [
    ( "a result without vernacularNames has an empty list",
      `Quick,
      fun () ->
        match
          Gbif.vernacular_search_of_json
            (gbif_page
               [`Assoc [("key", `Int 1); ("scientificName", `String "Foo bar")]])
        with
        | Ok {results = [(_, vernaculars)]; _} ->
            Alcotest.(check int) "vernaculars" 0 (List.length vernaculars)
        | Ok _ -> Alcotest.fail "expected exactly one result"
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
  ]

(* ---------- vernacular_names_of_json ---------- *)

let vernacular_names_tests =
  [
    ( "Digitalis purpurea: end_of_records, length, a German name, a \
       comma-joined TAXREF name kept unsplit",
      `Quick,
      fun () ->
        match Gbif.vernacular_names_of_json vernacular_names_digitalis with
        | Ok page ->
            Alcotest.(check bool) "end_of_records" true page.end_of_records;
            Alcotest.(check int) "length" 186 (List.length page.results);
            let has_deu =
              List.exists
                (fun (v : Gbif.Vernacular.t) ->
                  String.equal v.name "Roter Fingerhut"
                  && match v.language with Some "deu" -> true | _ -> false)
                page.results
            in
            Alcotest.(check bool) "Roter Fingerhut (deu) present" true has_deu;
            let has_comma_joined =
              List.exists
                (fun (v : Gbif.Vernacular.t) ->
                  Text.contains ~sub:", " v.name
                  &&
                  match v.source with
                  | Some s -> Text.contains ~sub:"TAXREF" s
                  | None -> false)
                page.results
            in
            Alcotest.(check bool)
              "a comma-joined TAXREF name is kept unsplit" true has_comma_joined
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "Arnica montana: end_of_records, length",
      `Quick,
      fun () ->
        match Gbif.vernacular_names_of_json vernacular_names_arnica with
        | Ok page ->
            Alcotest.(check bool) "end_of_records" true page.end_of_records;
            Alcotest.(check int) "length" 112 (List.length page.results)
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
  ]

let vernacular_names_inline_tests =
  [
    ( "rows with a missing or blank vernacularName are dropped, their errors \
       kept",
      `Quick,
      fun () ->
        Check.check_result "page" (page_t vernacular_t)
          (Ok
             {
               Gbif.results =
                 [
                   {
                     Gbif.Vernacular.name = "Foxglove";
                     language = Some "eng";
                     source = None;
                     country = None;
                   };
                 ];
               dropped =
                 [
                   Decode.Unexpected
                     {
                       path = "/results/0/vernacularName";
                       expected = "non-blank string";
                     };
                   Decode.Unexpected
                     {
                       path = "/results/1/vernacularName";
                       expected = "non-blank string";
                     };
                 ];
               end_of_records = true;
               count = None;
             })
          (Gbif.vernacular_names_of_json
             (gbif_page
                [
                  `Assoc [("vernacularName", `String "  ")];
                  `Assoc [("language", `String "fra")];
                  `Assoc
                    [
                      ("vernacularName", `String "Foxglove");
                      ("language", `String "eng");
                    ];
                ])) );
    ( "a missing endOfRecords is false, a count is kept",
      `Quick,
      fun () ->
        match
          Gbif.vernacular_names_of_json
            (`Assoc [("results", `List []); ("count", `Int 7)])
        with
        | Ok page ->
            Alcotest.(check bool) "end_of_records" false page.end_of_records;
            Alcotest.(check (option int)) "count" (Some 7) page.count
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "a missing results field is Unexpected at /results",
      `Quick,
      fun () ->
        check_unexpected_path "path" "/results"
          (Gbif.vernacular_names_of_json
             (`Assoc [("endOfRecords", `Bool true)])) );
  ]

(* ---------- distributions_of_json ---------- *)

let distributions_tests =
  [
    ( "Digitalis purpurea: end_of_records, length, a native WCVP row in France",
      `Quick,
      fun () ->
        match Gbif.distributions_of_json distributions_digitalis with
        | Ok page ->
            Alcotest.(check bool) "end_of_records" true page.end_of_records;
            Alcotest.(check int) "length" 193 (List.length page.results);
            let france_native =
              List.exists
                (fun (d : Gbif.Distribution.t) ->
                  Option.is_none d.establishment_means
                  && (match d.source with
                    | Some s -> Text.contains ~sub:"World Checklist" s
                    | None -> false)
                  &&
                  match d.locality with
                  | Some "France" -> true
                  | Some _ | None -> false)
                page.results
            in
            Alcotest.(check bool)
              "a native WCVP row for France exists" true france_native
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "Arnica montana: end_of_records, length, recorded number of WCVP rows",
      `Quick,
      fun () ->
        match Gbif.distributions_of_json distributions_arnica with
        | Ok page ->
            Alcotest.(check bool) "end_of_records" true page.end_of_records;
            Alcotest.(check int) "length" 144 (List.length page.results);
            let wcvp =
              List.filter
                (fun (d : Gbif.Distribution.t) ->
                  match d.source with
                  | Some s -> Text.contains ~sub:"World Checklist" s
                  | None -> false)
                page.results
            in
            Alcotest.(check int) "WCVP rows" 22 (List.length wcvp)
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "a country-only row is kept, a row with no location at all is dropped",
      `Quick,
      fun () ->
        match
          Gbif.distributions_of_json
            (gbif_page
               [
                 `Assoc
                   [
                     ("country", `String "FR");
                     ("threatStatus", `String "LEAST_CONCERN");
                   ];
                 `Assoc [("status", `String "PRESENT")];
               ])
        with
        | Ok page ->
            Alcotest.(check (list (option string)))
              "countries" [Some "FR"]
              (List.map
                 (fun (d : Gbif.Distribution.t) -> d.country)
                 page.results)
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "a non-array results field is an Error",
      `Quick,
      fun () ->
        check_is_error "results as string"
          (Gbif.distributions_of_json
             (`Assoc [("results", `String "x"); ("endOfRecords", `Bool true)]))
    );
  ]

(* ---------- occurrence_count_of_json ---------- *)

let occurrence_count_tests =
  [
    ( "Digitalis purpurea: the recorded count",
      `Quick,
      fun () ->
        Check.check_result "count" Alcotest.int (Ok 569133)
          (Gbif.occurrence_count_of_json occurrence_count_digitalis) );
    ( "Arnica montana: the recorded count",
      `Quick,
      fun () ->
        Check.check_result "count" Alcotest.int (Ok 232506)
          (Gbif.occurrence_count_of_json occurrence_count_arnica) );
    ( "a negative integer body is an Error",
      `Quick,
      fun () ->
        check_is_error "negative" (Gbif.occurrence_count_of_json (`Int (-1))) );
    ( "a string body is an Error",
      `Quick,
      fun () ->
        check_is_error "string" (Gbif.occurrence_count_of_json (`String "5")) );
    ( "zero is a count",
      `Quick,
      fun () ->
        Check.check_result "count" Alcotest.int (Ok 0)
          (Gbif.occurrence_count_of_json (`Int 0)) );
    ( "a float or an Intlit body is an Error",
      `Quick,
      fun () ->
        check_is_error "float" (Gbif.occurrence_count_of_json (`Float 5.));
        check_is_error "intlit"
          (Gbif.occurrence_count_of_json (`Intlit "3000000000")) );
    ( "a plantnet page without results is Unexpected at /results",
      `Quick,
      fun () ->
        check_unexpected_path "path" "/results"
          (Gbif.plantnet_media_of_json (`Assoc [("endOfRecords", `Bool true)]))
    );
  ]

(* ---------- plantnet_media_of_json ---------- *)

let count_by tbl key = Hashtbl.find_opt tbl key |> Option.value ~default:0
let bump tbl key = Hashtbl.replace tbl key (1 + count_by tbl key)

let organ_tally (images : Gbif.Image.t list) =
  let tbl = Hashtbl.create 8 in
  List.iter
    (fun (i : Gbif.Image.t) ->
      let key =
        match i.organ with None -> "none" | Some o -> Organ.to_string o
      in
      bump tbl key)
    images;
  tbl

let plantnet_media_tests =
  [
    ( "Digitalis purpurea: 53 images, the organ tally, the first occurrence \
       key above 2^31",
      `Quick,
      fun () ->
        match Gbif.plantnet_media_of_json plantnet_media_digitalis with
        | Ok page -> (
            Alcotest.(check int) "image count" 53 (List.length page.results);
            List.iter
              (fun (i : Gbif.Image.t) ->
                Alcotest.(check string) "licence" "cc-by-sa" i.licence;
                Alcotest.(check bool)
                  "attribution non-blank" true
                  (String.length (String.trim i.attribution) > 0);
                Alcotest.(check bool)
                  "url host" true
                  (String.starts_with ~prefix:"https://bs.plantnet.org/" i.url))
              page.results;
            let tbl = organ_tally page.results in
            Alcotest.(check int) "leaf" 49 (count_by tbl "leaf");
            Alcotest.(check int) "flower" 2 (count_by tbl "flower");
            Alcotest.(check int) "habit" 1 (count_by tbl "habit");
            Alcotest.(check int) "none (bark)" 1 (count_by tbl "none");
            match page.results with
            | first :: _ ->
                Alcotest.(check string)
                  "first occurrence_key" "5110295086" first.occurrence_key
            | [] -> Alcotest.fail "no images")
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "Arnica montana: 64 images, the organ tally",
      `Quick,
      fun () ->
        match Gbif.plantnet_media_of_json plantnet_media_arnica with
        | Ok page ->
            Alcotest.(check int) "image count" 64 (List.length page.results);
            let tbl = organ_tally page.results in
            Alcotest.(check int) "flower" 47 (count_by tbl "flower");
            Alcotest.(check int) "leaf" 12 (count_by tbl "leaf");
            Alcotest.(check int) "habit" 2 (count_by tbl "habit");
            Alcotest.(check int) "fruit" 1 (count_by tbl "fruit");
            Alcotest.(check int) "none (bark + other)" 2 (count_by tbl "none")
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "a media row whose license has no parenthesised licence is dropped",
      `Quick,
      fun () ->
        let occurrence =
          `Assoc
            [
              ("key", `Int 1);
              ( "media",
                `List
                  [
                    `Assoc
                      [
                        ("type", `String "StillImage");
                        ("identifier", `String "https://x/img.jpg");
                        ("license", `String "Someone");
                        ("title", `String "img: leaf");
                      ];
                  ] );
            ]
        in
        let page =
          `Assoc
            [
              ("results", `List [occurrence]);
              ("endOfRecords", `Bool true);
              ("count", `Int 1);
            ]
        in
        match Gbif.plantnet_media_of_json page with
        | Ok p -> Alcotest.(check int) "images" 0 (List.length p.results)
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "a media row that is not a StillImage is dropped",
      `Quick,
      fun () ->
        let occurrence =
          `Assoc
            [
              ("key", `Int 1);
              ( "media",
                `List
                  [
                    `Assoc
                      [
                        ("type", `String "Sound");
                        ("identifier", `String "https://x/a.mp3");
                        ("license", `String "Someone (cc-by-sa)");
                        ("rightsHolder", `String "Someone");
                      ];
                  ] );
            ]
        in
        let page =
          `Assoc
            [
              ("results", `List [occurrence]);
              ("endOfRecords", `Bool true);
              ("count", `Int 1);
            ]
        in
        match Gbif.plantnet_media_of_json page with
        | Ok p -> Alcotest.(check int) "images" 0 (List.length p.results)
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
  ]

let media ?(type_ = "StillImage") ?(identifier = "https://x/img.jpg") fields =
  `Assoc
    (("type", `String type_) :: ("identifier", `String identifier) :: fields
      : (string * Yojson.Safe.t) list)

let occurrence ?(key : Yojson.Safe.t option = Some (`Int 1)) ?references media =
  `Assoc
    ((match key with None -> [] | Some k -> [("key", k)])
    @ (match references with
      | None -> []
      | Some r -> [("references", `String r)])
    @ [("media", `List media)])

let images_of occurrences =
  match Gbif.plantnet_media_of_json (gbif_page occurrences) with
  | Ok p -> p.results
  | Error e -> Alcotest.failf "decode failed: %s" (Decode.error_to_string e)

let plantnet_media_inline_tests =
  [
    ( "a bark title gives organ_label bark and no organ",
      `Quick,
      fun () ->
        match
          images_of
            [
              occurrence
                [
                  media
                    [
                      ("license", `String "Iris Selcho (cc-by-sa)");
                      ("title", `String "Digitalis purpurea L.: bark");
                    ];
                ];
            ]
        with
        | [i] ->
            Alcotest.(check (option string))
              "organ_label" (Some "bark") i.organ_label;
            Alcotest.(check (option organ_t)) "organ" None i.organ;
            Alcotest.(check string) "licence" "cc-by-sa" i.licence;
            Alcotest.(check string)
              "attribution from the license holder" "Iris Selcho" i.attribution
        | l -> Alcotest.failf "expected 1 image, got %d" (List.length l) );
    ( "the recorded bark image of Digitalis has no organ",
      `Quick,
      fun () ->
        match Gbif.plantnet_media_of_json plantnet_media_digitalis with
        | Ok page ->
            Alcotest.(check (list (option organ_t)))
              "organs of bark images" [None]
              (List.filter_map
                 (fun (i : Gbif.Image.t) ->
                   match i.organ_label with
                   | Some "bark" -> Some i.organ
                   | Some _ | None -> None)
                 page.results)
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "an occurrence key above 2^31 sent as Intlit is kept as its digits",
      `Quick,
      fun () ->
        match
          images_of
            [
              occurrence
                ~key:(Some (`Intlit "5110295086"))
                [media [("license", `String "A (cc-by)")]];
            ]
        with
        | [i] ->
            Alcotest.(check string)
              "occurrence_key" "5110295086" i.occurrence_key
        | l -> Alcotest.failf "expected 1 image, got %d" (List.length l) );
    ( "an occurrence without a key is dropped with its media",
      `Quick,
      fun () ->
        Alcotest.(check int)
          "images" 0
          (List.length
             (images_of
                [
                  occurrence ~key:None [media [("license", `String "A (cc-by)")]];
                ])) );
    ( "an occurrence key that is negative or not digits is dropped, its error \
       kept",
      `Quick,
      fun () ->
        List.iter
          (fun key ->
            match
              Gbif.plantnet_media_of_json
                (gbif_page
                   [
                     occurrence ~key:(Some key)
                       [media [("license", `String "A (cc-by)")]];
                   ])
            with
            | Ok p ->
                Alcotest.(check int) "images" 0 (List.length p.results);
                Alcotest.(check (list string))
                  "dropped"
                  [
                    Decode.error_to_string
                      (Decode.Unexpected
                         {
                           path = "/results/0/key";
                           expected = "non-negative int";
                         });
                  ]
                  (List.map Decode.error_to_string p.dropped)
            | Error e ->
                Alcotest.failf "decode failed: %s" (Decode.error_to_string e))
          [`Int (-1); `Intlit "-5110295086"] );
    ( "a licence without a holder is kept, attributed to the rightsHolder",
      `Quick,
      fun () ->
        match
          images_of
            [
              occurrence
                [
                  media
                    [
                      ("license", `String "(cc-by)");
                      ("rightsHolder", `String "Someone");
                    ];
                ];
            ]
        with
        | [i] ->
            Alcotest.(check string) "licence" "cc-by" i.licence;
            Alcotest.(check string) "attribution" "Someone" i.attribution
        | l -> Alcotest.failf "expected 1 image, got %d" (List.length l) );
    ( "a licence without a holder and no other attribution is dropped",
      `Quick,
      fun () ->
        Alcotest.(check int)
          "images" 0
          (List.length
             (images_of
                [occurrence [media [("license", `String " (cc-by-sa)")]]])) );
    ( "a non-https identifier is dropped",
      `Quick,
      fun () ->
        Alcotest.(check int)
          "images" 0
          (List.length
             (images_of
                [
                  occurrence
                    [
                      media ~identifier:"http://x/img.jpg"
                        [("license", `String "A (cc-by)")];
                    ];
                ])) );
    ( "a licence code not starting with cc is dropped",
      `Quick,
      fun () ->
        Alcotest.(check int)
          "images" 0
          (List.length
             (images_of
                [occurrence [media [("license", `String "A (all rights)")]]]))
    );
    ( "the licence code is lower-cased",
      `Quick,
      fun () ->
        match
          images_of [occurrence [media [("license", `String "A (CC-BY-NC)")]]]
        with
        | [i] -> Alcotest.(check string) "licence" "cc-by-nc" i.licence
        | l -> Alcotest.failf "expected 1 image, got %d" (List.length l) );
    ( "attribution prefers rightsHolder, then creator, then the license holder",
      `Quick,
      fun () ->
        let attribution fields =
          match images_of [occurrence [media fields]] with
          | [i] -> i.attribution
          | l -> Alcotest.failf "expected 1 image, got %d" (List.length l)
        in
        let license = ("license", `String "Holder (cc-by)") in
        Alcotest.(check string)
          "rightsHolder" "Rights"
          (attribution
             [
               license;
               ("rightsHolder", `String "Rights");
               ("creator", `String "Creator");
             ]);
        Alcotest.(check string)
          "creator" "Creator"
          (attribution [license; ("creator", `String "Creator")]);
        Alcotest.(check string)
          "license holder" "Holder" (attribution [license]) );
    ( "no attribution anywhere is dropped",
      `Quick,
      fun () ->
        Alcotest.(check int)
          "images" 0
          (List.length
             (images_of
                [
                  occurrence
                    [
                      media
                        [
                          ("license", `String " (cc-by)");
                          ("rightsHolder", `String " ");
                        ];
                    ];
                ])) );
    ( "observation_url is the media source, else the occurrence references",
      `Quick,
      fun () ->
        let license = ("license", `String "A (cc-by)") in
        match
          images_of
            [
              occurrence ~references:"https://occ/1"
                [
                  media [license; ("source", `String "https://media/1")];
                  media [license];
                ];
            ]
        with
        | [a; b] ->
            Alcotest.(check (option string))
              "media source" (Some "https://media/1") a.observation_url;
            Alcotest.(check (option string))
              "occurrence references" (Some "https://occ/1") b.observation_url
        | l -> Alcotest.failf "expected 2 images, got %d" (List.length l) );
    ( "a title without a colon separator has no organ label",
      `Quick,
      fun () ->
        match
          images_of
            [
              occurrence
                [
                  media
                    [
                      ("license", `String "A (cc-by)"); ("title", `String "leaf");
                    ];
                ];
            ]
        with
        | [i] ->
            Alcotest.(check (option string)) "organ_label" None i.organ_label
        | l -> Alcotest.failf "expected 1 image, got %d" (List.length l) );
  ]

(* ---------- Decode.json_of_string ---------- *)

let decode_tests =
  [
    ( "invalid JSON text is Not_json",
      `Quick,
      fun () ->
        match Decode.json_of_string "{" with
        | Error (Not_json _) -> ()
        | Error e ->
            Alcotest.failf "expected Not_json, got %s"
              (Decode.error_to_string e)
        | Ok _ -> Alcotest.fail "expected Error" );
    ( "an empty body is Not_json, not an exception",
      `Quick,
      fun () ->
        match Decode.json_of_string "" with
        | Error (Not_json _) -> ()
        | Error e ->
            Alcotest.failf "expected Not_json, got %s"
              (Decode.error_to_string e)
        | Ok _ -> Alcotest.fail "expected Error" );
    ( "a bare integer is valid JSON",
      `Quick,
      fun () ->
        Check.check_result "parsed" Testable.yojson
          (Ok (`Int 569133))
          (Decode.json_of_string "569133") );
  ]

let suite =
  ( "gbif",
    species_tests
    @ status_tests
    @ match_tests
    @ suggest_tests
    @ vernacular_search_tests
    @ vernacular_search_inline_tests
    @ vernacular_names_tests
    @ vernacular_names_inline_tests
    @ distributions_tests
    @ occurrence_count_tests
    @ plantnet_media_tests
    @ plantnet_media_inline_tests
    @ decode_tests )
