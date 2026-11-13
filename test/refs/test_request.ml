module Request = Herbier_refs.Request
module Url = Herbier_net.Url
module Qid = Herbier_refs.Qid
module Gbif = Herbier_refs.Sources.Gbif
module Wikidata = Herbier_refs.Sources.Wikidata
module Wikipedia = Herbier_refs.Sources.Wikipedia
module Source = Herbier_domain.Reference.Source
module Fixture = Herbier_test_support.Fixture
module Text = Herbier_test_support.Text

let url (r : Request.t) = Request.(r.url)
let source_name (r : Request.t) = Source.to_string Request.(r.source)

let some name = function
  | Some r -> r
  | None -> Alcotest.failf "%s: expected Some" name

let request =
  Alcotest.testable
    (fun f r -> Format.pp_print_string f (Request.to_string r))
    Request.equal

(* ---------- Url.encode ---------- *)

let encode_tests =
  let case name input expected =
    ( name,
      `Quick,
      fun () -> Alcotest.(check string) name expected (Url.encode input) )
  in
  [
    case "space becomes %20, never +" "Digitalis purpurea L."
      "Digitalis%20purpurea%20L.";
    case "reserved punctuation is all encoded" "a/b?c&d=e#f"
      "a%2Fb%3Fc%26d%3De%23f";
    case "star is encoded" "*" "%2A";
    case "non-ASCII is UTF-8 then percent-encoded" "Pensée" "Pens%C3%A9e";
    case "the unreserved set is left as given" "AZaz09-._~" "AZaz09-._~";
    case "empty string" "" "";
    case "a literal plus is encoded, not left as +" "+" "%2B";
  ]

(* ---------- Request.make ---------- *)

let make_tests =
  [
    ( "equal compares source and URL; to_string shows both",
      `Quick,
      fun () ->
        let made source =
          Request.make source ~base:"https://api.gbif.org/v1"
            ~path:["species"; "5414995"] ~query:[]
        in
        Alcotest.check request "same request" (made Source.Gbif)
          (Gbif.species ~key:5414995);
        Alcotest.(check bool)
          "another source" false
          (Request.equal (made Source.Wikidata) (Gbif.species ~key:5414995));
        Alcotest.(check string)
          "to_string" "gbif https://api.gbif.org/v1/species/5414995"
          (Request.to_string (made Source.Gbif)) );
    ( "no path and no query renders the base alone",
      `Quick,
      fun () ->
        let r =
          Request.make Source.Gbif ~base:"https://api.gbif.org/v1" ~path:[]
            ~query:[]
        in
        Alcotest.(check string) "url" "https://api.gbif.org/v1" (url r) );
    ( "query parameters are rendered in the given order",
      `Quick,
      fun () ->
        let r =
          Request.make Source.Gbif ~base:"https://api.gbif.org/v1" ~path:[]
            ~query:[("b", "2"); ("a", "1")]
        in
        Alcotest.(check string) "url" "https://api.gbif.org/v1?b=2&a=1" (url r)
    );
    ( "path segments are each percent-encoded and slash-joined",
      `Quick,
      fun () ->
        let r =
          Request.make Source.Gbif ~base:"https://api.gbif.org/v1"
            ~path:["species"; "a b"] ~query:[]
        in
        Alcotest.(check string)
          "url" "https://api.gbif.org/v1/species/a%20b" (url r) );
  ]

(* ---------- every request function, exact URL ---------- *)

let gbif_backbone = "d7dddbf4-2cf0-4f39-9b2a-bb099caae36c"
let gbif_plantnet = "7a3679ef-5582-4aaa-81f0-8c2545cafc81"

let gbif_url_tests =
  [
    ( "species_url renders and classifies back to Link.Gbif",
      `Quick,
      fun () ->
        let u = Gbif.species_url 5414995 in
        Alcotest.(check string) "url" "https://www.gbif.org/species/5414995" u;
        Alcotest.(check bool)
          "Link.classify roundtrip" true
          Herbier_domain.Link.(equal (classify u) (Gbif 5414995)) );
    ( "species",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "url" "https://api.gbif.org/v1/species/5414995"
          (url (Gbif.species ~key:5414995)) );
    ( "match_name",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "url"
          "https://api.gbif.org/v1/species/match?name=Digitalis%20purpurea%20L.&kingdom=Plantae"
          (url
             (some "match_name" (Gbif.match_name ~name:"Digitalis purpurea L.")))
    );
    ( "match_name of a blank name is None",
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "blank" true
          (Option.is_none (Gbif.match_name ~name:"  ")) );
    ( "suggest",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "url"
          (Printf.sprintf
             "https://api.gbif.org/v1/species/suggest?q=Digitalis%%20purp&datasetKey=%s&rank=SPECIES&highertaxonKey=6&limit=10"
             gbif_backbone)
          (url (Gbif.suggest ~q:"Digitalis purp")) );
    ( "vernacular_search",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "url"
          (Printf.sprintf
             "https://api.gbif.org/v1/species/search?q=digitale%%20pourpre&datasetKey=%s&highertaxonKey=6&qField=VERNACULAR&limit=20"
             gbif_backbone)
          (url (Gbif.vernacular_search ~q:"digitale pourpre")) );
    ( "vernacular_names",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "url"
          "https://api.gbif.org/v1/species/5414995/vernacularNames?limit=1000"
          (url (Gbif.vernacular_names ~key:5414995)) );
    ( "distributions",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "url"
          "https://api.gbif.org/v1/species/5414995/distributions?limit=1000"
          (url (Gbif.distributions ~key:5414995)) );
    ( "occurrence_count",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "url" "https://api.gbif.org/v1/occurrence/count?taxonKey=5414995"
          (url (Gbif.occurrence_count ~key:5414995)) );
    ( "plantnet_media",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "url"
          (Printf.sprintf
             "https://api.gbif.org/v1/occurrence/search?datasetKey=%s&taxonKey=5414995&mediaType=StillImage&limit=50"
             gbif_plantnet)
          (url (Gbif.plantnet_media ~key:5414995)) );
    ( "every gbif request has source Gbif",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "source" "gbif"
          (source_name (Gbif.species ~key:1)) );
  ]

let wikidata_url_tests =
  [
    ( "search by gbif key",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "url"
          "https://www.wikidata.org/w/api.php?action=query&list=search&srsearch=haswbstatement%3A%22P846%3D5414995%22&format=json&origin=%2A"
          (url
             (some "search"
                (Wikidata.search ~property:Wikidata.Property.Gbif_key
                   ~value:"5414995"))) );
    ( "search by powo urn, colons stay inside the quoted statement",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "url"
          "https://www.wikidata.org/w/api.php?action=query&list=search&srsearch=haswbstatement%3A%22P5037%3Durn%3Alsid%3Aipni.org%3Anames%3A802077-1%22&format=json&origin=%2A"
          (url
             (some "search"
                (Wikidata.search ~property:Wikidata.Property.Powo
                   ~value:"urn:lsid:ipni.org:names:802077-1"))) );
    ( "search by taxref (P3186)",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "url"
          "https://www.wikidata.org/w/api.php?action=query&list=search&srsearch=haswbstatement%3A%22P3186%3D94959%22&format=json&origin=%2A"
          (url
             (some "search"
                (Wikidata.search ~property:Wikidata.Property.Taxref
                   ~value:"94959"))) );
    ( "search by tela (P3105)",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "url"
          "https://www.wikidata.org/w/api.php?action=query&list=search&srsearch=haswbstatement%3A%22P3105%3D22437%22&format=json&origin=%2A"
          (url
             (some "search"
                (Wikidata.search ~property:Wikidata.Property.Tela ~value:"22437")))
    );
    ( "search is None for a blank value",
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "blank" true
          (Option.is_none
             (Wikidata.search ~property:Wikidata.Property.Gbif_key ~value:""))
    );
    ( "search is None for a value that is only whitespace",
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "whitespace" true
          (Option.is_none
             (Wikidata.search ~property:Wikidata.Property.Gbif_key ~value:"  "))
    );
    ( "search is None for a value containing whitespace",
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "space" true
          (Option.is_none
             (Wikidata.search ~property:Wikidata.Property.Gbif_key ~value:"a b"))
    );
    ( "search is None for a value containing a quote",
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "quote" true
          (Option.is_none
             (Wikidata.search ~property:Wikidata.Property.Gbif_key
                ~value:{|a"b|})) );
    ( "entity",
      `Quick,
      fun () ->
        let qid = some "qid" (Qid.of_string "Q157555") in
        Alcotest.(check string)
          "url"
          "https://www.wikidata.org/w/api.php?action=wbgetentities&ids=Q157555&props=claims%7Csitelinks&sitefilter=frwiki%7Cenwiki%7Cdewiki%7Citwiki&format=json&origin=%2A"
          (url (Wikidata.entity qid)) );
    ( "every wikidata request has source Wikidata",
      `Quick,
      fun () ->
        let qid = some "qid" (Qid.of_string "Q1") in
        Alcotest.(check string)
          "source" "wikidata"
          (source_name (Wikidata.entity qid)) );
  ]

let wikipedia_url_tests =
  [
    ( "summary, fr",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "url"
          "https://fr.wikipedia.org/api/rest_v1/page/summary/Digitalis_purpurea"
          (url
             (some "summary"
                (Wikipedia.summary ~lang:"fr" ~title:"Digitalis purpurea"))) );
    ( "summary title is trimmed, spaces to underscores, then encoded as one \
       segment",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "url" "https://fr.wikipedia.org/api/rest_v1/page/summary/AC%2FDC"
          (url (some "summary" (Wikipedia.summary ~lang:"fr" ~title:" AC/DC ")))
    );
    ( "summary title with an accent is percent-encoded",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "url" "https://fr.wikipedia.org/api/rest_v1/page/summary/Pens%C3%A9e"
          (url (some "summary" (Wikipedia.summary ~lang:"fr" ~title:"Pensée")))
    );
    ( "a hyphenated lang code is accepted",
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "zh-min-nan" true
          (Option.is_some
             (Wikipedia.summary ~lang:"zh-min-nan" ~title:"Digitalis purpurea"))
    );
    ( "lang must be lower-case",
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "FR" true
          (Option.is_none
             (Wikipedia.summary ~lang:"FR" ~title:"Digitalis purpurea")) );
    ( "www is rejected explicitly",
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "www" true
          (Option.is_none
             (Wikipedia.summary ~lang:"www" ~title:"Digitalis purpurea")) );
    ( "a lang with a dot is rejected",
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "fr.m" true
          (Option.is_none
             (Wikipedia.summary ~lang:"fr.m" ~title:"Digitalis purpurea")) );
    ( "an empty lang is rejected",
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "empty" true
          (Option.is_none
             (Wikipedia.summary ~lang:"" ~title:"Digitalis purpurea")) );
    ( "a lang starting with a digit is rejected",
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "1fr" true
          (Option.is_none
             (Wikipedia.summary ~lang:"1fr" ~title:"Digitalis purpurea")) );
    ( "the longest real lang code (12 characters) is accepted",
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "zh-classical" true
          (Option.is_some
             (Wikipedia.summary ~lang:"zh-classical" ~title:"Digitalis purpurea"))
    );
    ( "a 13-character lang is rejected",
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "13 characters" true
          (Option.is_none
             (Wikipedia.summary ~lang:(String.make 13 'a')
                ~title:"Digitalis purpurea")) );
    ( "a dot-segment title is rejected",
      `Quick,
      fun () ->
        List.iter
          (fun title ->
            Alcotest.(check bool)
              title true
              (Option.is_none (Wikipedia.summary ~lang:"fr" ~title)))
          ["."; ".."; " .. "] );
    ( "a title of three dots is a page title, not a dot segment",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "url" "https://fr.wikipedia.org/api/rest_v1/page/summary/..."
          (url (some "summary" (Wikipedia.summary ~lang:"fr" ~title:"..."))) );
    ( "a blank title is rejected",
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "blank title" true
          (Option.is_none (Wikipedia.summary ~lang:"fr" ~title:"  ")) );
    ( "every wikipedia request has source Wikipedia",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "source" "wikipedia"
          (source_name
             (some "summary"
                (Wikipedia.summary ~lang:"fr" ~title:"Digitalis purpurea"))) );
  ]

(* ---------- Qid.of_string ---------- *)

let qid_tests =
  [
    ( "a well-formed qid is accepted and round-trips",
      `Quick,
      fun () ->
        match Qid.of_string "Q157555" with
        | Some q ->
            Alcotest.(check string) "round-trip" "Q157555" (Qid.to_string q)
        | None -> Alcotest.fail "Q157555 was rejected" );
    ( "Q0 is rejected (no leading zero digit)",
      `Quick,
      fun () ->
        Alcotest.(check bool) "Q0" true (Option.is_none (Qid.of_string "Q0")) );
    ( "a leading zero after Q is rejected",
      `Quick,
      fun () ->
        Alcotest.(check bool) "Q01" true (Option.is_none (Qid.of_string "Q01"))
    );
    ( "lower-case q is rejected",
      `Quick,
      fun () ->
        Alcotest.(check bool) "q1" true (Option.is_none (Qid.of_string "q1")) );
    ( "a property id is not an item id",
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "P846" true
          (Option.is_none (Qid.of_string "P846")) );
    ( "leading whitespace is rejected",
      `Quick,
      fun () ->
        Alcotest.(check bool) " Q1" true (Option.is_none (Qid.of_string " Q1"))
    );
    ( "Q alone with no digits is rejected",
      `Quick,
      fun () ->
        Alcotest.(check bool) "Q" true (Option.is_none (Qid.of_string "Q")) );
    ( "13 digits is one too many",
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "13 digits" true
          (Option.is_none (Qid.of_string "Q1234567890123")) );
  ]

(* ---------- recording script consistency ---------- *)

let script_path = "../../scripts/record-refs-fixtures.sh"

let read_script () =
  try Some (In_channel.with_open_bin script_path In_channel.input_all)
  with Sys_error _ -> None

(* Each fixture recorded from a request description, with that request: its
   fetch line must appear verbatim in the recording script. *)
let recorded_requests =
  [
    ("gbif_species_5414995.json", Gbif.species ~key:5414995);
    ("gbif_species_5405976.json", Gbif.species ~key:5405976);
    ("gbif_species_5334357.json", Gbif.species ~key:5334357);
    ("gbif_species_2889173.json", Gbif.species ~key:2889173);
    ("gbif_species_7971454.json", Gbif.species ~key:7971454);
    ("gbif_species_5708907.json", Gbif.species ~key:5708907);
    ( "gbif_match_digitalis_purpurea_l.json",
      some "match" (Gbif.match_name ~name:"Digitalis purpurea L.") );
    ( "gbif_match_digitalis_purpurae.json",
      some "match" (Gbif.match_name ~name:"Digitalis purpurae") );
    ( "gbif_match_fallopia_japonica.json",
      some "match" (Gbif.match_name ~name:"Fallopia japonica") );
    ( "gbif_match_xyzzy_foo.json",
      some "match" (Gbif.match_name ~name:"Xyzzy foo") );
    ("gbif_suggest_digitalis_purp.json", Gbif.suggest ~q:"Digitalis purp");
    ("gbif_suggest_digitale_pourpre.json", Gbif.suggest ~q:"digitale pourpre");
    ( "gbif_vernacular_search_digitale_pourpre.json",
      Gbif.vernacular_search ~q:"digitale pourpre" );
    ( "gbif_vernacular_search_digitalis_purp.json",
      Gbif.vernacular_search ~q:"Digitalis purp" );
    ("gbif_vernacular_names_5414995.json", Gbif.vernacular_names ~key:5414995);
    ("gbif_vernacular_names_5405976.json", Gbif.vernacular_names ~key:5405976);
    ("gbif_distributions_5414995.json", Gbif.distributions ~key:5414995);
    ("gbif_distributions_5405976.json", Gbif.distributions ~key:5405976);
    ("gbif_occurrence_count_5414995.json", Gbif.occurrence_count ~key:5414995);
    ("gbif_occurrence_count_5405976.json", Gbif.occurrence_count ~key:5405976);
    ("gbif_plantnet_media_5414995.json", Gbif.plantnet_media ~key:5414995);
    ("gbif_plantnet_media_5405976.json", Gbif.plantnet_media ~key:5405976);
    ("gbif_plantnet_media_1.json", Gbif.plantnet_media ~key:1);
    ( "wikidata_search_p846_5414995.json",
      some "p846_5414995"
        (Wikidata.search ~property:Wikidata.Property.Gbif_key ~value:"5414995")
    );
    ( "wikidata_search_p846_5405976.json",
      some "p846_5405976"
        (Wikidata.search ~property:Wikidata.Property.Gbif_key ~value:"5405976")
    );
    ( "wikidata_search_p5037_802077-1.json",
      some "p5037"
        (Wikidata.search ~property:Wikidata.Property.Powo
           ~value:"urn:lsid:ipni.org:names:802077-1") );
    ( "wikidata_search_p846_999999999.json",
      some "p846_999999999"
        (Wikidata.search ~property:Wikidata.Property.Gbif_key ~value:"999999999")
    );
    ( "wikidata_search_p3151_53983.json",
      some "p3151"
        (Wikidata.search ~property:Wikidata.Property.Inat ~value:"53983") );
    ( "wikidata_search_p3186_94959.json",
      some "p3186"
        (Wikidata.search ~property:Wikidata.Property.Taxref ~value:"94959") );
    ( "wikidata_search_p3105_22437.json",
      some "p3105"
        (Wikidata.search ~property:Wikidata.Property.Tela ~value:"22437") );
    ( "wikidata_entity_Q157555.json",
      Wikidata.entity (some "Q157555" (Qid.of_string "Q157555")) );
    ( "wikidata_entity_Q207848.json",
      Wikidata.entity (some "Q207848" (Qid.of_string "Q207848")) );
    ( "wikipedia_summary_fr_Digitalis_purpurea.json",
      some "fr digitalis"
        (Wikipedia.summary ~lang:"fr" ~title:"Digitalis purpurea") );
    ( "wikipedia_summary_fr_Arnica_montana.json",
      some "fr arnica" (Wikipedia.summary ~lang:"fr" ~title:"Arnica montana") );
    ( "wikipedia_summary_fr_Arnica_des_montagnes.json",
      some "fr arnica sitelink"
        (Wikipedia.summary ~lang:"fr" ~title:"Arnica des montagnes") );
    ( "wikipedia_summary_en_Digitalis_purpurea.json",
      some "en digitalis"
        (Wikipedia.summary ~lang:"en" ~title:"Digitalis purpurea") );
    ( "wikipedia_summary_fr_Lis.json",
      some "fr lis" (Wikipedia.summary ~lang:"fr" ~title:"Lis") );
  ]

(* Recorded by a URL no request function builds (no kingdom filter; Q0 is not
   a Qid.t): only their existence is checked. *)
let fixtures_without_request =
  ["gbif_match_none_zzzzqqq.json"; "wikidata_entity_Q0.json"]

let script_tests =
  [
    ( "every recorded request's fetch line appears in the recording script",
      `Quick,
      fun () ->
        match read_script () with
        | None ->
            Alcotest.fail
              "scripts/record-refs-fixtures.sh is missing: cannot check \
               fixture URLs against it"
        | Some script ->
            List.iter
              (fun (file, request) ->
                let line =
                  Printf.sprintf "fetch %s %s \"%s\"" file (source_name request)
                    (url request)
                in
                match Text.contains ~sub:line script with
                | true -> ()
                | false ->
                    Alcotest.failf "%s: line %s not found in %s" file line
                      script_path)
              recorded_requests );
    ( "every recorded fixture exists in test/fixtures/",
      `Quick,
      fun () ->
        List.iter
          (fun (file, _) ->
            match Fixture.exists file with
            | true -> ()
            | false -> Alcotest.failf "missing fixture test/fixtures/%s" file)
          recorded_requests;
        List.iter
          (fun file ->
            match Fixture.exists file with
            | true -> ()
            | false -> Alcotest.failf "missing fixture test/fixtures/%s" file)
          fixtures_without_request );
  ]

let suite =
  ( "request",
    encode_tests
    @ make_tests
    @ gbif_url_tests
    @ wikidata_url_tests
    @ wikipedia_url_tests
    @ qid_tests
    @ script_tests )
