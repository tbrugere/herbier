(* Herbier_refs.Resolve: Link.t + network lookups -> the GBIF taxon
   (architecture §7), over Fake_net. One test per path, each pinning the
   exact request list made. *)

module Resolve = Herbier_refs.Resolve
module Step = Herbier_refs.Step
module Request = Herbier_refs.Request
module Decode = Herbier_refs.Decode
module Gbif = Herbier_refs.Sources.Gbif
module Wikidata = Herbier_refs.Sources.Wikidata
module Wikipedia = Herbier_refs.Sources.Wikipedia
module Qid = Herbier_refs.Qid
module Link = Herbier_domain.Link
module Fixture = Herbier_test_support.Fixture

let some name = function
  | Some r -> r
  | None -> Alcotest.failf "%s: expected Some" name

let url (r : Request.t) = Request.(r.url)
let qid157555 = some "qid" (Qid.of_string "Q157555")

let fixture_body file : Yojson.Safe.t =
  match Decode.json_of_string (Fixture.read file) with
  | Ok j -> j
  | Error e -> Alcotest.failf "%s: %s" file (Decode.error_to_string e)

let base_fail (r : Request.t) : Step.response =
  Alcotest.failf "unexpected request %s" (url r)

(* [only overrides] answers exactly the given URLs; any other request fails
   the test, so a test using it asserts "no other call is made". *)
let only overrides = Fake_net.with_ overrides base_fail
let run_resolve net link = Step.run net (Resolve.resolve link)

let requests_of net link =
  List.map
    (fun (r : Request.t) -> r.url)
    (Step.requests net (Resolve.resolve link))

(* ---------- rendering, for readable failures ---------- *)

let why_string : Resolve.unresolved -> string = function
  | No_species -> "No_species"
  | Observation_link -> "Observation_link"
  | Unavailable m -> "Unavailable " ^ m

let outcome_json : Resolve.outcome -> Yojson.Safe.t = function
  | Taxon (t : Gbif.Taxon.t) ->
      `Assoc
        [
          ( "Taxon",
            `Assoc
              [
                ("key", `Int t.key);
                ("scientific_name", `String t.scientific_name);
              ] );
        ]
  | Candidates taxa ->
      `Assoc
        [
          ( "Candidates",
            `List (List.map (fun (t : Gbif.Taxon.t) -> `Int t.key) taxa) );
        ]
  | Unresolved {query; why} ->
      `Assoc
        [
          ( "Unresolved",
            `Assoc [("query", `String query); ("why", `String (why_string why))]
          );
        ]

let show o = Yojson.Safe.to_string (outcome_json o)

let check_taxon_key ~what key = function
  | Resolve.Taxon (t : Gbif.Taxon.t) -> Alcotest.(check int) what key t.key
  | o -> Alcotest.failf "%s: expected Taxon %d, got %s" what key (show o)

(* ---------- Gbif ---------- *)

let gbif_simple () =
  let net =
    Fake_net.fixtures
      [(url (Gbif.species ~key:5414995), "gbif_species_5414995.json")]
  in
  (match run_resolve net (Link.Gbif 5414995) with
  | Resolve.Taxon (t : Gbif.Taxon.t) ->
      Alcotest.(check int) "key" 5414995 t.key;
      Alcotest.(check (option string))
        "canonical_name" (Some "Digitalis purpurea") t.canonical_name;
      Alcotest.(check (option string)) "family" (Some "Plantaginaceae") t.family
  | o -> Alcotest.failf "expected Taxon, got %s" (show o));
  Alcotest.(check (list string))
    "requests"
    [url (Gbif.species ~key:5414995)]
    (requests_of net (Link.Gbif 5414995))

let gbif_synonym_followed_one_hop () =
  let net =
    Fake_net.fixtures
      [
        (url (Gbif.species ~key:5334357), "gbif_species_5334357.json");
        (url (Gbif.species ~key:2889173), "gbif_species_2889173.json");
      ]
  in
  check_taxon_key ~what:"gbif synonym" 2889173
    (run_resolve net (Link.Gbif 5334357));
  Alcotest.(check (list string))
    "species, then the accepted species"
    [url (Gbif.species ~key:5334357); url (Gbif.species ~key:2889173)]
    (requests_of net (Link.Gbif 5334357))

let gbif_species_absent_is_no_species () =
  let net = only [(url (Gbif.species ~key:999), Step.Absent)] in
  match run_resolve net (Link.Gbif 999) with
  | Resolve.Unresolved {query; why = Resolve.No_species} ->
      Alcotest.(check string) "query" "" query
  | o -> Alcotest.failf "expected Unresolved No_species, got %s" (show o)

let gbif_species_failed_is_unavailable () =
  let net = only [(url (Gbif.species ~key:5414995), Step.Failed "x")] in
  match run_resolve net (Link.Gbif 5414995) with
  | Resolve.Unresolved {why = Resolve.Unavailable _; _} -> ()
  | o -> Alcotest.failf "expected Unresolved Unavailable, got %s" (show o)

(* ---------- Plantnet / Plantuse (name match) ---------- *)

let plantnet_exact_match_accepted_no_species_call () =
  let name = "Digitalis purpurea L." in
  let net =
    Fake_net.fixtures
      [
        ( url (some "match" (Gbif.match_name ~name)),
          "gbif_match_digitalis_purpurea_l.json" );
      ]
  in
  check_taxon_key ~what:"plantnet exact" 5414995
    (run_resolve net (Link.Plantnet name));
  Alcotest.(check int)
    "one request (accepted, no species call)" 1
    (List.length (requests_of net (Link.Plantnet name)))

let plantuse_synonym_followed () =
  let name = "Fallopia japonica" in
  let net =
    Fake_net.fixtures
      [
        ( url (some "match" (Gbif.match_name ~name)),
          "gbif_match_fallopia_japonica.json" );
        (url (Gbif.species ~key:2889173), "gbif_species_2889173.json");
      ]
  in
  check_taxon_key ~what:"plantuse synonym" 2889173
    (run_resolve net (Link.Plantuse name))

let plantnet_higher_rank_is_no_species () =
  let name = "Xyzzy foo" in
  let net =
    Fake_net.fixtures
      [
        (url (some "match" (Gbif.match_name ~name)), "gbif_match_xyzzy_foo.json");
      ]
  in
  match run_resolve net (Link.Plantnet name) with
  | Resolve.Unresolved {query; why = Resolve.No_species} ->
      Alcotest.(check string) "query" name query
  | o -> Alcotest.failf "expected Unresolved No_species, got %s" (show o)

let plantnet_fuzzy_match_accepted () =
  let name = "Digitalis purpurae" in
  let net =
    Fake_net.fixtures
      [
        ( url (some "match" (Gbif.match_name ~name)),
          "gbif_match_digitalis_purpurae.json" );
      ]
  in
  check_taxon_key ~what:"plantnet fuzzy" 5414995
    (run_resolve net (Link.Plantnet name))

let plantnet_blank_name_no_call () =
  let name = "  " in
  let net = only [] in
  match run_resolve net (Link.Plantnet name) with
  | Resolve.Unresolved {query; why = Resolve.No_species} ->
      Alcotest.(check string) "query, as given, not trimmed" name query
  | o -> Alcotest.failf "expected Unresolved No_species, got %s" (show o)

(* ---------- Wikipedia ---------- *)

let wikipedia_resolves_via_wikidata () =
  let net =
    Fake_net.fixtures
      [
        ( url
            (some "summary"
               (Wikipedia.summary ~lang:"fr" ~title:"Digitalis purpurea")),
          "wikipedia_summary_fr_Digitalis_purpurea.json" );
        (url (Wikidata.entity qid157555), "wikidata_entity_Q157555.json");
        (url (Gbif.species ~key:5414995), "gbif_species_5414995.json");
      ]
  in
  check_taxon_key ~what:"wikipedia" 5414995
    (run_resolve net
       (Link.Wikipedia {lang = "fr"; title = "Digitalis purpurea"}))

let wikipedia_disambiguation_is_no_species_no_wikidata_call () =
  let net =
    Fake_net.fixtures
      [
        ( url (some "summary" (Wikipedia.summary ~lang:"fr" ~title:"Lis")),
          "wikipedia_summary_fr_Lis.json" );
      ]
  in
  let link = Link.Wikipedia {lang = "fr"; title = "Lis"} in
  (match run_resolve net link with
  | Resolve.Unresolved {query; why = Resolve.No_species} ->
      Alcotest.(check string) "query" "Lis" query
  | o -> Alcotest.failf "expected Unresolved No_species, got %s" (show o));
  Alcotest.(check int)
    "summary only, no wikidata call" 1
    (List.length (requests_of net link))

let wikipedia_summary_absent_is_no_species () =
  let title = "Nonexistent Page" in
  let net =
    only
      [
        (url (some "summary" (Wikipedia.summary ~lang:"fr" ~title)), Step.Absent);
      ]
  in
  match run_resolve net (Link.Wikipedia {lang = "fr"; title}) with
  | Resolve.Unresolved {query; why = Resolve.No_species} ->
      Alcotest.(check string) "query" title query
  | o -> Alcotest.failf "expected Unresolved No_species, got %s" (show o)

(* ---------- Powo / Inat / Inpn / Tela, via Wikidata (architecture §7) ---------- *)

let via_wikidata_property ~what ~property ~value ~search_file link =
  let net =
    Fake_net.fixtures
      [
        (url (some "search" (Wikidata.search ~property ~value)), search_file);
        (url (Wikidata.entity qid157555), "wikidata_entity_Q157555.json");
        (url (Gbif.species ~key:5414995), "gbif_species_5414995.json");
      ]
  in
  check_taxon_key ~what 5414995 (run_resolve net link)

let powo_resolves () =
  via_wikidata_property ~what:"powo" ~property:Wikidata.Property.Powo
    ~value:"urn:lsid:ipni.org:names:802077-1"
    ~search_file:"wikidata_search_p5037_802077-1.json"
    (Link.Powo "urn:lsid:ipni.org:names:802077-1")

let inat_resolves () =
  via_wikidata_property ~what:"inat" ~property:Wikidata.Property.Inat
    ~value:"53983" ~search_file:"wikidata_search_p3151_53983.json"
    (Link.Inat 53983)

let inpn_resolves () =
  via_wikidata_property ~what:"inpn" ~property:Wikidata.Property.Taxref
    ~value:"94959" ~search_file:"wikidata_search_p3186_94959.json"
    (Link.Inpn 94959)

let tela_resolves () =
  via_wikidata_property ~what:"tela" ~property:Wikidata.Property.Tela
    ~value:"22437" ~search_file:"wikidata_search_p3105_22437.json"
    (Link.Tela 22437)

let inat_empty_search_is_no_species () =
  let body = fixture_body "wikidata_search_p846_999999999.json" in
  let net =
    only
      [
        ( url
            (some "search"
               (Wikidata.search ~property:Wikidata.Property.Inat ~value:"1")),
          Step.Body body );
      ]
  in
  match run_resolve net (Link.Inat 1) with
  | Resolve.Unresolved {query; why = Resolve.No_species} ->
      Alcotest.(check string) "query" "" query
  | o -> Alcotest.failf "expected Unresolved No_species, got %s" (show o)

(* ---------- Plantnet_observation ---------- *)

let plantnet_observation_is_unresolved_no_call () =
  let net = only [] in
  match run_resolve net (Link.Plantnet_observation "123") with
  | Resolve.Unresolved {query; why = Resolve.Observation_link} ->
      Alcotest.(check string) "query" "" query
  | o -> Alcotest.failf "expected Unresolved Observation_link, got %s" (show o)

(* ---------- Text (candidates) ---------- *)

let keys_of (taxa : Gbif.Taxon.t list) =
  List.map (fun (t : Gbif.Taxon.t) -> t.key) taxa

let check_candidates what expected = function
  | Resolve.Candidates taxa ->
      Alcotest.(check (list int)) what expected (keys_of taxa)
  | o -> Alcotest.failf "%s: expected Candidates, got %s" what (show o)

let no_dup_keys what (taxa : Gbif.Taxon.t list) =
  let keys = List.map (fun (t : Gbif.Taxon.t) -> t.key) taxa in
  Alcotest.(check int)
    (what ^ ": no duplicate key")
    (List.length keys)
    (List.length (List.sort_uniq Int.compare keys))

let text_digitale_pourpre_candidates () =
  let q = "digitale pourpre" in
  let net =
    Fake_net.fixtures
      [
        (url (Gbif.suggest ~q), "gbif_suggest_digitale_pourpre.json");
        ( url (Gbif.vernacular_search ~q),
          "gbif_vernacular_search_digitale_pourpre.json" );
      ]
  in
  (* suggest answers [] for a vernacular name; the vernacular search's
     three taxa follow, 5414995 among them. *)
  check_candidates "suggest's taxa, then the vernacular ones"
    [10263161; 5708907; 5414995]
    (run_resolve net (Link.Text q));
  Alcotest.(check (list string))
    "suggest, then vernacular search"
    [url (Gbif.suggest ~q); url (Gbif.vernacular_search ~q)]
    (requests_of net (Link.Text q))

let text_digitalis_purp_candidates_suggest_first () =
  let q = "Digitalis purp" in
  let net =
    Fake_net.fixtures
      [
        (url (Gbif.suggest ~q), "gbif_suggest_digitalis_purp.json");
        ( url (Gbif.vernacular_search ~q),
          "gbif_vernacular_search_digitalis_purp.json" );
      ]
  in
  (* the vernacular search finds nothing for a Latin prefix: suggest's
     six taxa, in its order. *)
  check_candidates "suggest's order"
    [5414995; 7549341; 8296187; 7971454; 7354417; 8192969]
    (run_resolve net (Link.Text q))

let text_both_failed_is_unavailable () =
  let q = "x" in
  let net =
    only
      [
        (url (Gbif.suggest ~q), Step.Failed "x");
        (url (Gbif.vernacular_search ~q), Step.Failed "x");
      ]
  in
  match run_resolve net (Link.Text q) with
  | Resolve.Unresolved {query; why = Resolve.Unavailable _} ->
      Alcotest.(check string) "query" q query
  | o -> Alcotest.failf "expected Unresolved Unavailable, got %s" (show o)

let text_suggest_failed_falls_back_to_vernacular () =
  let q = "digitale pourpre" in
  let base =
    Fake_net.fixtures
      [
        ( url (Gbif.vernacular_search ~q),
          "gbif_vernacular_search_digitale_pourpre.json" );
      ]
  in
  let net = Fake_net.with_ [(url (Gbif.suggest ~q), Step.Failed "x")] base in
  check_candidates "the vernacular taxa"
    [10263161; 5708907; 5414995]
    (run_resolve net (Link.Text q))

let text_blank_is_empty_candidates_no_call () =
  let net = only [] in
  match run_resolve net (Link.Text "") with
  | Resolve.Candidates [] -> ()
  | o -> Alcotest.failf "expected Candidates [], got %s" (show o)

(* ---------- species_ranks, candidates dedup on its own ---------- *)

let species_ranks_content () =
  Alcotest.(check (list string))
    "species_ranks"
    [
      "SPECIES";
      "SUBSPECIES";
      "VARIETY";
      "SUBVARIETY";
      "FORM";
      "SUBFORM";
      "INFRASPECIFIC_NAME";
    ]
    Resolve.species_ranks

let candidates_dedup_on_its_own () =
  (* Overlapping answers: suggest's Digitalis list, and the "digitale
     pourpre" vernacular page (which also holds 5414995) given as the
     vernacular answer. 5414995 is listed once, at suggest's place. *)
  let q = "Digitalis purp" in
  let net =
    Fake_net.with_
      [
        ( url (Gbif.vernacular_search ~q),
          Step.Body
            (Fake_net.json_of_fixture
               "gbif_vernacular_search_digitale_pourpre.json") );
      ]
      (Fake_net.fixtures
         [(url (Gbif.suggest ~q), "gbif_suggest_digitalis_purp.json")])
  in
  match Step.run net (Resolve.candidates ~q) with
  | Ok taxa ->
      Alcotest.(check (list int))
        "suggest's taxa, then the vernacular ones not already listed"
        [
          5414995; 7549341; 8296187; 7971454; 7354417; 8192969; 10263161; 5708907;
        ]
        (keys_of taxa);
      no_dup_keys "candidates ~q" taxa
  | Error e -> Alcotest.failf "expected Ok, got Error %s" (why_string e)

let candidates_both_failed_first_message () =
  let q = "x" in
  let net =
    only
      [
        (url (Gbif.suggest ~q), Step.Failed "suggest down");
        (url (Gbif.vernacular_search ~q), Step.Failed "search down");
      ]
  in
  match Step.run net (Resolve.candidates ~q) with
  | Error (Resolve.Unavailable e) ->
      Alcotest.(check string) "the first message" "suggest down" e
  | Error e -> Alcotest.failf "expected Unavailable, got %s" (why_string e)
  | Ok _ -> Alcotest.fail "expected Error"

let candidates_vernacular_failed_keeps_suggest () =
  let q = "Digitalis purp" in
  let net =
    Fake_net.with_
      [(url (Gbif.vernacular_search ~q), Step.Failed "x")]
      (Fake_net.fixtures
         [(url (Gbif.suggest ~q), "gbif_suggest_digitalis_purp.json")])
  in
  match Step.run net (Resolve.candidates ~q) with
  | Ok taxa ->
      Alcotest.(check (list int))
        "suggest's taxa"
        [5414995; 7549341; 8296187; 7971454; 7354417; 8192969]
        (keys_of taxa)
  | Error e -> Alcotest.failf "expected Ok, got Error %s" (why_string e)

(* ---------- remaining No_species / Unavailable paths ---------- *)

let fr_digitalis_summary () =
  url
    (some "summary" (Wikipedia.summary ~lang:"fr" ~title:"Digitalis purpurea"))

let entity_body () = Fake_net.json_of_fixture "wikidata_entity_Q157555.json"
let digitalis_link = Link.Wikipedia {lang = "fr"; title = "Digitalis purpurea"}

let expect_no_species ~query = function
  | Resolve.Unresolved {query = q; why = Resolve.No_species} ->
      Alcotest.(check string) "query" query q
  | o -> Alcotest.failf "expected Unresolved No_species, got %s" (show o)

let expect_unavailable ~query = function
  | Resolve.Unresolved {query = q; why = Resolve.Unavailable _} ->
      Alcotest.(check string) "query" query q
  | o -> Alcotest.failf "expected Unresolved Unavailable, got %s" (show o)

let wikipedia_without_item_is_no_species () =
  let summary =
    Fake_net.without ["wikibase_item"]
      (Fake_net.json_of_fixture "wikipedia_summary_fr_Digitalis_purpurea.json")
  in
  let net = only [(fr_digitalis_summary (), Step.Body summary)] in
  expect_no_species ~query:"Digitalis purpurea" (run_resolve net digitalis_link);
  Alcotest.(check int)
    "summary only" 1
    (List.length (requests_of net digitalis_link))

let wikipedia_entity_without_p846_is_no_species () =
  let entity =
    Fake_net.without ["entities"; "Q157555"; "claims"; "P846"] (entity_body ())
  in
  let net =
    Fake_net.with_
      [(url (Wikidata.entity qid157555), Step.Body entity)]
      (Fake_net.fixtures
         [
           ( fr_digitalis_summary (),
             "wikipedia_summary_fr_Digitalis_purpurea.json" );
         ])
  in
  expect_no_species ~query:"Digitalis purpurea" (run_resolve net digitalis_link);
  Alcotest.(check (list string))
    "summary, entity; no species call"
    [fr_digitalis_summary (); url (Wikidata.entity qid157555)]
    (requests_of net digitalis_link)

let wikipedia_entity_missing_is_no_species () =
  let missing =
    `Assoc
      [
        ( "entities",
          `Assoc
            [
              ( "Q157555",
                `Assoc [("id", `String "Q157555"); ("missing", `String "")] );
            ] );
      ]
  in
  let net =
    Fake_net.with_
      [(url (Wikidata.entity qid157555), Step.Body missing)]
      (Fake_net.fixtures
         [
           ( fr_digitalis_summary (),
             "wikipedia_summary_fr_Digitalis_purpurea.json" );
         ])
  in
  expect_no_species ~query:"Digitalis purpurea" (run_resolve net digitalis_link)

let wikipedia_entity_failed_is_unavailable () =
  let net =
    Fake_net.with_
      [(url (Wikidata.entity qid157555), Step.Failed "x")]
      (Fake_net.fixtures
         [
           ( fr_digitalis_summary (),
             "wikipedia_summary_fr_Digitalis_purpurea.json" );
         ])
  in
  expect_unavailable ~query:"Digitalis purpurea"
    (run_resolve net digitalis_link)

let powo_id_with_whitespace_no_call () =
  let net = only [] in
  expect_no_species ~query:"" (run_resolve net (Link.Powo "urn:lsid ipni"))

let inat_search_failed_is_unavailable () =
  let net =
    only
      [
        ( url
            (some "search"
               (Wikidata.search ~property:Wikidata.Property.Inat ~value:"53983")),
          Step.Failed "x" );
      ]
  in
  expect_unavailable ~query:"" (run_resolve net (Link.Inat 53983))

let synonym_accepted_absent_is_no_species () =
  let net =
    Fake_net.with_
      [(url (Gbif.species ~key:2889173), Step.Absent)]
      (Fake_net.fixtures
         [(url (Gbif.species ~key:5334357), "gbif_species_5334357.json")])
  in
  expect_no_species ~query:"" (run_resolve net (Link.Gbif 5334357))

let match_failed_is_unavailable () =
  let name = "Digitalis purpurea L." in
  let net =
    only [(url (some "match" (Gbif.match_name ~name)), Step.Failed "x")]
  in
  expect_unavailable ~query:name (run_resolve net (Link.Plantnet name))

let species_undecodable_is_unavailable () =
  let net = only [(url (Gbif.species ~key:5414995), Step.Body (`String "x"))] in
  expect_unavailable ~query:"" (run_resolve net (Link.Gbif 5414995))

(* ---------- the rank guard, synonym hops, candidate failures ---------- *)

(* [json] with the member [key] of its root object set to [value]. *)
let set_member key value (json : Yojson.Safe.t) : Yojson.Safe.t =
  match json with
  | `Assoc kvs -> `Assoc ((key, value) :: List.remove_assoc key kvs)
  | _ -> Alcotest.failf "set_member %s: not an object" key

let digitalis_match () =
  Fake_net.json_of_fixture "gbif_match_digitalis_purpurea_l.json"

let match_net name body =
  only [(url (some "match" (Gbif.match_name ~name)), Step.Body body)]

let plantnet_exact_match_at_genus_rank_is_no_species () =
  let name = "Digitalis purpurea L." in
  let net =
    match_net name (set_member "rank" (`String "GENUS") (digitalis_match ()))
  in
  expect_no_species ~query:name (run_resolve net (Link.Plantnet name));
  Alcotest.(check int)
    "the match alone" 1
    (List.length (requests_of net (Link.Plantnet name)))

let plantnet_exact_match_without_rank_accepted () =
  let name = "Digitalis purpurea L." in
  let net = match_net name (Fake_net.without ["rank"] (digitalis_match ())) in
  check_taxon_key ~what:"no rank" 5414995 (run_resolve net (Link.Plantnet name))

let synonym_body ~key ~accepted =
  set_member "acceptedKey" (`Int accepted)
    (set_member "key" (`Int key)
       (Fake_net.json_of_fixture "gbif_species_5334357.json"))

let synonym_of_itself_not_followed () =
  let net =
    only
      [
        ( url (Gbif.species ~key:5334357),
          Step.Body (synonym_body ~key:5334357 ~accepted:5334357) );
      ]
  in
  check_taxon_key ~what:"self synonym" 5334357
    (run_resolve net (Link.Gbif 5334357));
  Alcotest.(check int)
    "one request" 1
    (List.length (requests_of net (Link.Gbif 5334357)))

let synonym_chain_followed_one_hop_only () =
  (* 2889173 served as a synonym of 777, which is not served: a second hop
     would fail the test with "unexpected request". *)
  let net =
    Fake_net.with_
      [
        ( url (Gbif.species ~key:2889173),
          Step.Body (synonym_body ~key:2889173 ~accepted:777) );
      ]
      (Fake_net.fixtures
         [(url (Gbif.species ~key:5334357), "gbif_species_5334357.json")])
  in
  check_taxon_key ~what:"one hop" 2889173 (run_resolve net (Link.Gbif 5334357));
  Alcotest.(check int)
    "two requests" 2
    (List.length (requests_of net (Link.Gbif 5334357)))

(* The "digitale pourpre" vernacular page with its first result repeated at
   the end. *)
let vernacular_with_repeat () =
  match
    Fake_net.json_of_fixture "gbif_vernacular_search_digitale_pourpre.json"
  with
  | `Assoc kvs as json -> (
      match List.assoc_opt "results" kvs with
      | Some (`List (first :: _ as results)) ->
          set_member "results" (`List (results @ [first])) json
      | _ -> Alcotest.fail "vernacular fixture: no results")
  | _ -> Alcotest.fail "vernacular fixture: not an object"

let candidates_vernacular_repeat_listed_once () =
  let q = "Digitalis purp" in
  let net =
    Fake_net.with_
      [(url (Gbif.vernacular_search ~q), Step.Body (vernacular_with_repeat ()))]
      (Fake_net.fixtures
         [(url (Gbif.suggest ~q), "gbif_suggest_digitalis_purp.json")])
  in
  match Step.run net (Resolve.candidates ~q) with
  | Ok taxa ->
      Alcotest.(check (list int))
        "10263161 once, at its first place"
        [
          5414995; 7549341; 8296187; 7971454; 7354417; 8192969; 10263161; 5708907;
        ]
        (keys_of taxa)
  | Error e -> Alcotest.failf "expected Ok, got Error %s" (why_string e)

let candidates_suggest_failed_vernacular_repeat_listed_once () =
  let q = "digitale pourpre" in
  let net =
    only
      [
        (url (Gbif.suggest ~q), Step.Failed "x");
        (url (Gbif.vernacular_search ~q), Step.Body (vernacular_with_repeat ()));
      ]
  in
  match Step.run net (Resolve.candidates ~q) with
  | Ok taxa ->
      Alcotest.(check (list int))
        "each key once"
        [10263161; 5708907; 5414995]
        (keys_of taxa)
  | Error e -> Alcotest.failf "expected Ok, got Error %s" (why_string e)

let text_empty_suggest_and_failed_vernacular_is_unavailable () =
  let q = "digitale pourpre" in
  let net =
    Fake_net.with_
      [(url (Gbif.vernacular_search ~q), Step.Failed "HTTP 503")]
      (Fake_net.fixtures
         [(url (Gbif.suggest ~q), "gbif_suggest_digitale_pourpre.json")])
  in
  expect_unavailable ~query:q (run_resolve net (Link.Text q))

(* ---------- search / Candidate, chosen (4i / 4k / 5c) ---------- *)

module Candidate = Resolve.Candidate

let candidate_keys (cs : Candidate.t list) =
  List.map (fun (c : Candidate.t) -> c.taxon.key) cs

let candidate_french (cs : Candidate.t list) key =
  match List.find_opt (fun (c : Candidate.t) -> c.taxon.key = key) cs with
  | Some c -> c.french
  | None -> Alcotest.failf "no candidate of key %d" key

let search_requests net q =
  List.map
    (fun (r : Request.t) -> r.url)
    (Step.requests net (Resolve.search ~q))

let taxon_of_species file =
  match Gbif.species_of_json (Fake_net.json_of_fixture file) with
  | Ok t -> t
  | Error e -> Alcotest.failf "%s: %s" file (Decode.error_to_string e)

let suggest_taxon ~key file =
  match Gbif.suggest_of_json (Fake_net.json_of_fixture file) with
  | Ok taxa -> (
      match List.find_opt (fun (t : Gbif.Taxon.t) -> t.key = key) taxa with
      | Some t -> t
      | None -> Alcotest.failf "%s: no taxon of key %d" file key)
  | Error e -> Alcotest.failf "%s: %s" file (Decode.error_to_string e)

let run_chosen net taxon = Step.run net (Resolve.chosen taxon)

let chosen_requests net taxon =
  List.map
    (fun (r : Request.t) -> r.url)
    (Step.requests net (Resolve.chosen taxon))

let chosen_result_string = function
  | Ok (t : Gbif.Taxon.t) -> Printf.sprintf "Ok %d" t.key
  | Error e -> "Error " ^ why_string e

let search_digitalis_purp_matches_candidates_french_empty () =
  let q = "Digitalis purp" in
  let net =
    Fake_net.fixtures
      [
        (url (Gbif.suggest ~q), "gbif_suggest_digitalis_purp.json");
        ( url (Gbif.vernacular_search ~q),
          "gbif_vernacular_search_digitalis_purp.json" );
      ]
  in
  (match Step.run net (Resolve.search ~q) with
  | Ok cs ->
      Alcotest.(check (list int))
        "same taxa as candidates ~q"
        [5414995; 7549341; 8296187; 7971454; 7354417; 8192969]
        (candidate_keys cs);
      List.iter
        (fun (c : Candidate.t) ->
          Alcotest.(check (list string))
            (Printf.sprintf "french of %d empty" c.taxon.key)
            [] c.french)
        cs
  | Error e -> Alcotest.failf "expected Ok, got Error %s" (why_string e));
  Alcotest.(check (list string))
    "suggest, then vernacular search"
    [url (Gbif.suggest ~q); url (Gbif.vernacular_search ~q)]
    (search_requests net q)

let search_digitale_pourpre_french_names () =
  let q = "digitale pourpre" in
  let net =
    Fake_net.fixtures
      [
        (url (Gbif.suggest ~q), "gbif_suggest_digitale_pourpre.json");
        ( url (Gbif.vernacular_search ~q),
          "gbif_vernacular_search_digitale_pourpre.json" );
      ]
  in
  match Step.run net (Resolve.search ~q) with
  | Ok cs ->
      Alcotest.(check (list int))
        "taxa as candidates"
        [10263161; 5708907; 5414995]
        (candidate_keys cs);
      Alcotest.(check (list string))
        "french of 5708907"
        ["Digitale pourpre"; "Gantelée"; "Gant de Notre-Dame"]
        (candidate_french cs 5708907);
      Alcotest.(check (list string))
        "french of 5414995"
        [
          "Digitale pourpre";
          "Gantelée";
          "Gant de Notre-Dame";
          "Digitale";
          "Digitale pourprée";
          "grande digitale";
          "Digitale à fleurs blanches";
        ]
        (candidate_french cs 5414995);
      Alcotest.(check (list string))
        "french of 10263161 (one name listed twice)"
        ["Hybride entre la Digitale à petites fleurs et la Digitale pourpre"]
        (candidate_french cs 10263161)
  | Error e -> Alcotest.failf "expected Ok, got Error %s" (why_string e)

let search_suggest_failed_falls_back_to_vernacular () =
  let q = "digitale pourpre" in
  let base =
    Fake_net.fixtures
      [
        ( url (Gbif.vernacular_search ~q),
          "gbif_vernacular_search_digitale_pourpre.json" );
      ]
  in
  let net = Fake_net.with_ [(url (Gbif.suggest ~q), Step.Failed "x")] base in
  match Step.run net (Resolve.search ~q) with
  | Ok cs ->
      Alcotest.(check (list int))
        "vernacular's taxa"
        [10263161; 5708907; 5414995]
        (candidate_keys cs);
      Alcotest.(check (list string))
        "french of 5708907 kept"
        ["Digitale pourpre"; "Gantelée"; "Gant de Notre-Dame"]
        (candidate_french cs 5708907)
  | Error e -> Alcotest.failf "expected Ok, got Error %s" (why_string e)

let search_both_failed_is_unavailable () =
  let q = "x" in
  let net =
    only
      [
        (url (Gbif.suggest ~q), Step.Failed "x");
        (url (Gbif.vernacular_search ~q), Step.Failed "x");
      ]
  in
  match Step.run net (Resolve.search ~q) with
  | Error (Resolve.Unavailable _) -> ()
  | Ok _ -> Alcotest.fail "expected Error, got Ok"
  | Error e -> Alcotest.failf "expected Unavailable, got %s" (why_string e)

let search_vernacular_failed_keeps_suggest_french_empty () =
  let q = "Digitalis purp" in
  let net =
    Fake_net.with_
      [(url (Gbif.vernacular_search ~q), Step.Failed "x")]
      (Fake_net.fixtures
         [(url (Gbif.suggest ~q), "gbif_suggest_digitalis_purp.json")])
  in
  match Step.run net (Resolve.search ~q) with
  | Ok cs ->
      Alcotest.(check (list int))
        "suggest's taxa"
        [5414995; 7549341; 8296187; 7971454; 7354417; 8192969]
        (candidate_keys cs);
      List.iter
        (fun (c : Candidate.t) ->
          Alcotest.(check (list string))
            (Printf.sprintf "french of %d empty" c.taxon.key)
            [] c.french)
        cs
  | Error e -> Alcotest.failf "expected Ok, got Error %s" (why_string e)

let search_blank_is_empty_no_call () =
  List.iter
    (fun q ->
      let net = only [] in
      (match Step.run net (Resolve.search ~q) with
      | Ok [] -> ()
      | Ok _ -> Alcotest.failf "%S: expected Ok []" q
      | Error e ->
          Alcotest.failf "%S: expected Ok [], got Error %s" q (why_string e));
      Alcotest.(check (list string))
        (Printf.sprintf "%S: no request" q)
        [] (search_requests net q))
    [""; "   "]

let chosen_synonym_from_species_followed_one_hop () =
  let taxon = taxon_of_species "gbif_species_7971454.json" in
  let net =
    Fake_net.fixtures
      [
        (url (Gbif.species ~key:7971454), "gbif_species_7971454.json");
        (url (Gbif.species ~key:5708907), "gbif_species_5708907.json");
      ]
  in
  (match run_chosen net taxon with
  | Ok (t : Gbif.Taxon.t) -> Alcotest.(check int) "accepted key" 5708907 t.key
  | Error e -> Alcotest.failf "expected Ok, got Error %s" (why_string e));
  Alcotest.(check (list string))
    "species, then the accepted species"
    [url (Gbif.species ~key:7971454); url (Gbif.species ~key:5708907)]
    (chosen_requests net taxon)

let chosen_synonym_from_suggest_same_result () =
  let taxon = suggest_taxon ~key:7971454 "gbif_suggest_digitalis_purp.json" in
  Alcotest.(check (option int))
    "suggest omits acceptedKey" None taxon.accepted_key;
  let net =
    Fake_net.fixtures
      [
        (url (Gbif.species ~key:7971454), "gbif_species_7971454.json");
        (url (Gbif.species ~key:5708907), "gbif_species_5708907.json");
      ]
  in
  (match run_chosen net taxon with
  | Ok (t : Gbif.Taxon.t) -> Alcotest.(check int) "accepted key" 5708907 t.key
  | Error e -> Alcotest.failf "expected Ok, got Error %s" (why_string e));
  Alcotest.(check (list string))
    "same two requests as from the species decoder"
    [url (Gbif.species ~key:7971454); url (Gbif.species ~key:5708907)]
    (chosen_requests net taxon)

let chosen_accepted_taxon_no_call () =
  let taxon = suggest_taxon ~key:5414995 "gbif_suggest_digitalis_purp.json" in
  let net = only [] in
  (match run_chosen net taxon with
  | Ok (t : Gbif.Taxon.t) -> Alcotest.(check int) "itself" 5414995 t.key
  | Error e -> Alcotest.failf "expected Ok, got Error %s" (why_string e));
  Alcotest.(check (list string)) "no request" [] (chosen_requests net taxon)

let chosen_other_statuses_no_call () =
  List.iter
    (fun (what, status) ->
      let taxon =
        {
          (suggest_taxon ~key:5414995 "gbif_suggest_digitalis_purp.json") with
          Gbif.Taxon.status;
        }
      in
      let net = only [] in
      (match run_chosen net taxon with
      | Ok (t : Gbif.Taxon.t) ->
          Alcotest.(check int) (what ^ ": itself") 5414995 t.key
      | Error e ->
          Alcotest.failf "%s: expected Ok, got Error %s" what (why_string e));
      Alcotest.(check (list string))
        (what ^ ": no request") []
        (chosen_requests net taxon))
    [
      ("Accepted", Some Gbif.Status.Accepted);
      ("Doubtful", Some Gbif.Status.Doubtful);
      ("Other", Some (Gbif.Status.Other "PROPARTE_SYNONYM"));
      ("None", None);
    ]

let chosen_synonym_species_absent_is_no_species () =
  let taxon = suggest_taxon ~key:7971454 "gbif_suggest_digitalis_purp.json" in
  let net = only [(url (Gbif.species ~key:7971454), Step.Absent)] in
  match run_chosen net taxon with
  | Error Resolve.No_species -> ()
  | r ->
      Alcotest.failf "expected Error No_species, got %s"
        (chosen_result_string r)

let chosen_synonym_accepted_absent_or_failed () =
  let taxon = taxon_of_species "gbif_species_7971454.json" in
  List.iter
    (fun (what, response, expected) ->
      let net =
        Fake_net.with_
          [(url (Gbif.species ~key:5708907), response)]
          (Fake_net.fixtures
             [(url (Gbif.species ~key:7971454), "gbif_species_7971454.json")])
      in
      match run_chosen net taxon with
      | Error e when String.equal (why_string e) expected -> ()
      | r ->
          Alcotest.failf "%s: expected Error %s, got %s" what expected
            (chosen_result_string r))
    [
      ("Absent", Step.Absent, why_string Resolve.No_species);
      ("Failed", Step.Failed "x", why_string (Resolve.Unavailable "x"));
    ]

let chosen_synonym_species_failed_is_unavailable () =
  let taxon = suggest_taxon ~key:7971454 "gbif_suggest_digitalis_purp.json" in
  let net = only [(url (Gbif.species ~key:7971454), Step.Failed "x")] in
  match run_chosen net taxon with
  | Error (Resolve.Unavailable "x") -> ()
  | r ->
      Alcotest.failf "expected Error (Unavailable \"x\"), got %s"
        (chosen_result_string r)

let chosen_synonym_species_undecodable_is_unavailable () =
  let taxon = suggest_taxon ~key:7971454 "gbif_suggest_digitalis_purp.json" in
  let net = only [(url (Gbif.species ~key:7971454), Step.Body (`List []))] in
  match run_chosen net taxon with
  | Error (Resolve.Unavailable _) -> ()
  | r ->
      Alcotest.failf "expected Error (Unavailable _), got %s"
        (chosen_result_string r)

(* ---------- named (4j's French name, architecture §7) ---------- *)

let run_named net taxon : Candidate.t * string option =
  Step.run net (Resolve.named taxon)

let check_taxon_kept what (expected : Gbif.Taxon.t) (got : Gbif.Taxon.t) =
  Alcotest.(check int) (what ^ "taxon key") expected.key got.key;
  Alcotest.(check string)
    (what ^ "taxon scientific_name")
    expected.scientific_name got.scientific_name

let named_requests net taxon =
  List.map
    (fun (r : Request.t) -> r.url)
    (Step.requests net (Resolve.named taxon))

let named_digitalis_french_names () =
  let taxon = taxon_of_species "gbif_species_5414995.json" in
  let net =
    Fake_net.fixtures
      [
        ( url (Gbif.vernacular_names ~key:5414995),
          "gbif_vernacular_names_5414995.json" );
      ]
  in
  let c, failure = run_named net taxon in
  check_taxon_kept "" taxon c.taxon;
  Alcotest.(check (option string)) "no failure" None failure;
  Alcotest.(check (list string))
    "french"
    [
      "Digitale pourpre";
      "Digitale";
      "Digitale pourprée";
      "Gantelée";
      "Gant de Notre-Dame";
      "Digitale à fleurs blanches";
      "grande digitale";
    ]
    c.french;
  Alcotest.(check (list string))
    "exactly one request"
    [url (Gbif.vernacular_names ~key:5414995)]
    (named_requests net taxon)

let named_arnica_french_names () =
  let taxon = taxon_of_species "gbif_species_5405976.json" in
  let net =
    Fake_net.fixtures
      [
        ( url (Gbif.vernacular_names ~key:5405976),
          "gbif_vernacular_names_5405976.json" );
      ]
  in
  let c, failure = run_named net taxon in
  check_taxon_kept "" taxon c.taxon;
  Alcotest.(check (option string)) "no failure" None failure;
  Alcotest.(check (list string))
    "french"
    ["Arnica"; "Arnica des montagnes"; "Herbe aux prêcheurs"]
    c.french

let named_absent_is_empty_french () =
  let taxon = taxon_of_species "gbif_species_5414995.json" in
  let net = only [(url (Gbif.vernacular_names ~key:5414995), Step.Absent)] in
  let c, failure = run_named net taxon in
  check_taxon_kept "" taxon c.taxon;
  Alcotest.(check (list string)) "french = []" [] c.french;
  Alcotest.(check (option string)) "Absent is no failure" None failure

let named_failed_is_empty_french () =
  let taxon = taxon_of_species "gbif_species_5414995.json" in
  let net =
    only [(url (Gbif.vernacular_names ~key:5414995), Step.Failed "timeout")]
  in
  let c, failure = run_named net taxon in
  check_taxon_kept "" taxon c.taxon;
  Alcotest.(check (list string)) "french = []" [] c.french;
  Alcotest.(check (option string))
    "the failure, for the console" (Some "timeout") failure

let named_undecodable_body_is_empty_french () =
  let taxon = taxon_of_species "gbif_species_5414995.json" in
  List.iter
    (fun (what, body) ->
      let net =
        only [(url (Gbif.vernacular_names ~key:5414995), Step.Body body)]
      in
      let c, failure = run_named net taxon in
      check_taxon_kept (what ^ ": ") taxon c.taxon;
      Alcotest.(check (list string)) (what ^ ": french = []") [] c.french;
      Alcotest.(check bool)
        (what ^ ": the decode error is returned")
        true (Option.is_some failure))
    [
      ( "a species body served at the vernacularNames url",
        Fake_net.json_of_fixture "gbif_species_5414995.json" );
      ("a bare JSON string", `String "x");
    ]

(* ---------- run ---------- *)

let case name f = (name, `Quick, f)

let suite =
  ( "resolve",
    [
      case "Gbif: species, key/canonical_name/family" gbif_simple;
      case "Gbif on a synonym key: followed one hop to the accepted species"
        gbif_synonym_followed_one_hop;
      case "Gbif: species Absent is Unresolved No_species"
        gbif_species_absent_is_no_species;
      case "Gbif: species Failed is Unresolved Unavailable"
        gbif_species_failed_is_unavailable;
      case "Plantnet: exact match accepted directly, no species call"
        plantnet_exact_match_accepted_no_species_call;
      case "Plantuse: a synonym match is followed to the accepted species"
        plantuse_synonym_followed;
      case "Plantnet: a match above species rank is Unresolved No_species"
        plantnet_higher_rank_is_no_species;
      case "Plantnet: a fuzzy match is accepted" plantnet_fuzzy_match_accepted;
      case "Plantnet: a blank name makes no call, query given as is"
        plantnet_blank_name_no_call;
      case "Wikipedia: summary -> wikidata entity -> gbif species"
        wikipedia_resolves_via_wikidata;
      case "Wikipedia: a disambiguation page is No_species, no wikidata call"
        wikipedia_disambiguation_is_no_species_no_wikidata_call;
      case "Wikipedia: summary Absent is Unresolved No_species"
        wikipedia_summary_absent_is_no_species;
      case "Powo: resolved through Wikidata P5037" powo_resolves;
      case "Inat: resolved through Wikidata P3151" inat_resolves;
      case "Inpn: resolved through Wikidata P3186 (TaxRef)" inpn_resolves;
      case "Tela: resolved through Wikidata P3105" tela_resolves;
      case "Inat: an empty Wikidata search is Unresolved No_species"
        inat_empty_search_is_no_species;
      case "Plantnet_observation: Unresolved Observation_link, no call"
        plantnet_observation_is_unresolved_no_call;
      case
        "Text: suggest then vernacular search, 5414995 among the candidates, \
         no duplicate"
        text_digitale_pourpre_candidates;
      case "Text: suggest's order leads, vernacular adds the rest"
        text_digitalis_purp_candidates_suggest_first;
      case "Text: both calls failed is Unresolved Unavailable"
        text_both_failed_is_unavailable;
      case "Text: suggest failed falls back to the vernacular results"
        text_suggest_failed_falls_back_to_vernacular;
      case "Text: blank text is Candidates [] without a call"
        text_blank_is_empty_candidates_no_call;
      case "species_ranks content" species_ranks_content;
      case "candidates ~q dedup, on its own" candidates_dedup_on_its_own;
      case "candidates ~q: both calls failed is Error with the first message"
        candidates_both_failed_first_message;
      case "candidates ~q: vernacular failed keeps suggest's taxa"
        candidates_vernacular_failed_keeps_suggest;
      case
        "Wikipedia: a summary without wikibase_item is No_species, no wikidata \
         call"
        wikipedia_without_item_is_no_species;
      case "Wikipedia: an entity without P846 is No_species, no species call"
        wikipedia_entity_without_p846_is_no_species;
      case "Wikipedia: a missing entity is No_species"
        wikipedia_entity_missing_is_no_species;
      case "Wikipedia: entity Failed is Unavailable, query = title"
        wikipedia_entity_failed_is_unavailable;
      case "Powo: an id with whitespace is No_species without a call"
        powo_id_with_whitespace_no_call;
      case "Inat: Wikidata search Failed is Unavailable"
        inat_search_failed_is_unavailable;
      case "Gbif synonym whose accepted species is Absent is No_species"
        synonym_accepted_absent_is_no_species;
      case "Plantnet: match Failed is Unavailable, query = name"
        match_failed_is_unavailable;
      case "Gbif: an undecodable species body is Unavailable"
        species_undecodable_is_unavailable;
      case "Plantnet: an EXACT match at GENUS rank is No_species, one request"
        plantnet_exact_match_at_genus_rank_is_no_species;
      case "Plantnet: an EXACT match without a rank is accepted"
        plantnet_exact_match_without_rank_accepted;
      case "Gbif: a synonym of itself is not followed"
        synonym_of_itself_not_followed;
      case "Gbif: a synonym's accepted synonym is not followed (one hop)"
        synonym_chain_followed_one_hop_only;
      case
        "candidates ~q: a key repeated in the vernacular results is listed once"
        candidates_vernacular_repeat_listed_once;
      case
        "candidates ~q: suggest failed, a repeated vernacular key is listed \
         once"
        candidates_suggest_failed_vernacular_repeat_listed_once;
      case "Text: suggest [] and vernacular search Failed is Unavailable"
        text_empty_suggest_and_failed_vernacular_is_unavailable;
      case
        "search ~q: same taxa as candidates ~q, every french = [], suggest \
         then vernacular"
        search_digitalis_purp_matches_candidates_french_empty;
      case "search ~q: french names from the vernacular search page"
        search_digitale_pourpre_french_names;
      case "search ~q: suggest failed falls back to the vernacular candidates"
        search_suggest_failed_falls_back_to_vernacular;
      case "search ~q: both calls failed is Error (Unavailable _)"
        search_both_failed_is_unavailable;
      case "search ~q: vernacular failed keeps suggest's taxa, french = []"
        search_vernacular_failed_keeps_suggest_french_empty;
      case "search ~q: blank q is Ok [] without a call"
        search_blank_is_empty_no_call;
      case
        "chosen: a synonym from the species decoder is followed one hop to its \
         accepted taxon"
        chosen_synonym_from_species_followed_one_hop;
      case
        "chosen: a synonym from the suggest decoder (no acceptedKey) gives the \
         same requests and result"
        chosen_synonym_from_suggest_same_result;
      case "chosen: an Accepted taxon is Ok itself, no request"
        chosen_accepted_taxon_no_call;
      case
        "chosen: Accepted, Doubtful, Other or no status is Ok itself, no \
         request"
        chosen_other_statuses_no_call;
      case "chosen: a synonym's species call Absent is Error No_species"
        chosen_synonym_species_absent_is_no_species;
      case
        "chosen: the accepted species call Absent or Failed is Error \
         No_species or Unavailable"
        chosen_synonym_accepted_absent_or_failed;
      case "chosen: a synonym's species call Failed is Error (Unavailable _)"
        chosen_synonym_species_failed_is_unavailable;
      case "chosen: an undecodable species body is Error (Unavailable _)"
        chosen_synonym_species_undecodable_is_unavailable;
      case
        "named: Digitalis purpurea (5414995), french names from \
         vernacularNames, one request"
        named_digitalis_french_names;
      case "named: Arnica (5405976), french names from vernacularNames"
        named_arnica_french_names;
      case "named: vernacularNames Absent is french = [], taxon kept"
        named_absent_is_empty_french;
      case "named: vernacularNames Failed is french = [], taxon kept"
        named_failed_is_empty_french;
      case "named: an undecodable vernacularNames body is french = []"
        named_undecodable_body_is_empty_french;
    ] )
