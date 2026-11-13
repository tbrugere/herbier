module Decode = Herbier_refs.Decode
module Qid = Herbier_refs.Qid
module Wikidata = Herbier_refs.Sources.Wikidata

let qid_t = Alcotest.testable Qid.pp Qid.equal
let entity_t = Alcotest.testable Wikidata.Entity.pp Wikidata.Entity.equal
let search_p846_5414995 = Check.json "wikidata_search_p846_5414995.json"
let search_p846_5405976 = Check.json "wikidata_search_p846_5405976.json"
let search_p5037 = Check.json "wikidata_search_p5037_802077-1.json"
let search_p846_none = Check.json "wikidata_search_p846_999999999.json"
let entity_q157555 = Check.json "wikidata_entity_Q157555.json"
let entity_q207848 = Check.json "wikidata_entity_Q207848.json"
let entity_q0 = Check.json "wikidata_entity_Q0.json"

(* ---------- search_of_json ---------- *)

let search_tests =
  [
    ( "P846 = 5414995 finds Q157555",
      `Quick,
      fun () ->
        Check.check_result "qids" (Alcotest.list qid_t)
          (Ok [Check.some_qid "q" "Q157555"])
          (Wikidata.search_of_json search_p846_5414995) );
    ( "P846 = 5405976 finds Q207848",
      `Quick,
      fun () ->
        Check.check_result "qids" (Alcotest.list qid_t)
          (Ok [Check.some_qid "q" "Q207848"])
          (Wikidata.search_of_json search_p846_5405976) );
    ( "P5037 (POWO urn) finds the same Digitalis item",
      `Quick,
      fun () ->
        Check.check_result "qids" (Alcotest.list qid_t)
          (Ok [Check.some_qid "q" "Q157555"])
          (Wikidata.search_of_json search_p5037) );
    ( "no hit is an empty list, not an error",
      `Quick,
      fun () ->
        Check.check_result "qids" (Alcotest.list qid_t) (Ok [])
          (Wikidata.search_of_json search_p846_none) );
    ( "a root error object is Api_error",
      `Quick,
      fun () ->
        let j =
          `Assoc
            [("error", `Assoc [("code", `String "x"); ("info", `String "y")])]
        in
        match Wikidata.search_of_json j with
        | Error (Decode.Api_error {code; info}) ->
            Alcotest.(check string) "code" "x" code;
            Alcotest.(check string) "info" "y" info
        | Error e ->
            Alcotest.failf "expected Api_error, got %s"
              (Decode.error_to_string e)
        | Ok _ -> Alcotest.fail "expected Error" );
    ( "hits whose title is not a Qid are dropped, order kept",
      `Quick,
      fun () ->
        let hit t = `Assoc [("title", `String t)] in
        Check.check_result "qids" (Alcotest.list qid_t)
          (Ok [Check.some_qid "q" "Q2"; Check.some_qid "q" "Q1"])
          (Wikidata.search_of_json
             (`Assoc
                [
                  ( "query",
                    `Assoc
                      [
                        ( "search",
                          `List
                            [hit "Q2"; hit "Property:P846"; `Assoc []; hit "Q1"]
                        );
                      ] );
                ])) );
    ( "a missing query.search array is Unexpected at /query/search",
      `Quick,
      fun () ->
        match Wikidata.search_of_json (`Assoc []) with
        | Error (Decode.Unexpected {path; _}) ->
            Alcotest.(check string) "path" "/query/search" path
        | Error e ->
            Alcotest.failf "expected Unexpected, got %s"
              (Decode.error_to_string e)
        | Ok _ -> Alcotest.fail "expected Error" );
  ]

(* ---------- entity_of_json ---------- *)

let find_sitelink (e : Wikidata.Entity.t) lang =
  List.find_opt
    (fun (s : Wikidata.Entity.sitelink) -> String.equal s.lang lang)
    e.sitelinks

let entity_tests =
  [
    ( "Digitalis purpurea entity: every cross-id",
      `Quick,
      fun () ->
        match Wikidata.entity_of_json entity_q157555 with
        | Ok (Some e) ->
            Alcotest.(check bool)
              "qid" true
              (Qid.equal e.qid (Check.some_qid "q" "Q157555"));
            Alcotest.(check (option int)) "gbif_key" (Some 5414995) e.gbif_key;
            Alcotest.(check (option string))
              "powo" (Some "urn:lsid:ipni.org:names:802077-1") e.powo;
            Alcotest.(check (option string)) "ipni" (Some "802077-1") e.ipni;
            Alcotest.(check (option int)) "taxref" (Some 94959) e.taxref;
            Alcotest.(check (option int)) "tela" (Some 22437) e.tela;
            Alcotest.(check (option string)) "eppo" (Some "DIKPU") e.eppo;
            Alcotest.(check (option int)) "inat" (Some 53983) e.inat;
            Alcotest.(check (list string))
              "sitelink langs, in order" ["fr"; "en"; "de"; "it"]
              (List.map
                 (fun (s : Wikidata.Entity.sitelink) -> s.lang)
                 e.sitelinks);
            Alcotest.(check (option string))
              "fr title" (Some "Digitalis purpurea")
              (Option.map
                 (fun (s : Wikidata.Entity.sitelink) -> s.title)
                 (find_sitelink e "fr"));
            Alcotest.(check (option string))
              "de title" (Some "Roter Fingerhut")
              (Option.map
                 (fun (s : Wikidata.Entity.sitelink) -> s.title)
                 (find_sitelink e "de"));
            let has_de_common_name =
              List.exists
                (fun (n : Wikidata.Entity.name) ->
                  String.equal n.lang "de"
                  && String.equal n.text "Roter Fingerhut")
                e.common_names
            in
            Alcotest.(check bool)
              "common_names has de Roter Fingerhut" true has_de_common_name
        | Ok None -> Alcotest.fail "expected Some"
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "Arnica montana entity: every cross-id",
      `Quick,
      fun () ->
        match Wikidata.entity_of_json entity_q207848 with
        | Ok (Some e) ->
            Alcotest.(check (option int)) "gbif_key" (Some 5405976) e.gbif_key;
            Alcotest.(check (option string))
              "powo" (Some "urn:lsid:ipni.org:names:30090722-2") e.powo;
            Alcotest.(check (option string)) "ipni" (Some "30090722-2") e.ipni;
            Alcotest.(check (option int)) "taxref" (Some 83874) e.taxref;
            Alcotest.(check (option int)) "tela" (Some 6648) e.tela;
            Alcotest.(check (option string)) "eppo" (Some "ARXMO") e.eppo;
            Alcotest.(check (option int)) "inat" (Some 56229) e.inat;
            Alcotest.(check (option string))
              "fr title" (Some "Arnica des montagnes")
              (Option.map
                 (fun (s : Wikidata.Entity.sitelink) -> s.title)
                 (find_sitelink e "fr"));
            Alcotest.(check (option string))
              "de title" (Some "Arnika")
              (Option.map
                 (fun (s : Wikidata.Entity.sitelink) -> s.title)
                 (find_sitelink e "de"));
            let has_fr_common_name =
              List.exists
                (fun (n : Wikidata.Entity.name) ->
                  String.equal n.lang "fr"
                  && String.equal n.text "Arnica des montagnes")
                e.common_names
            in
            Alcotest.(check bool)
              "common_names has fr Arnica des montagnes" true has_fr_common_name
        | Ok None -> Alcotest.fail "expected Some"
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "Q0 (no such entity) is Api_error no-such-entity",
      `Quick,
      fun () ->
        match Wikidata.entity_of_json entity_q0 with
        | Error (Decode.Api_error {code; _}) ->
            Alcotest.(check string) "code" "no-such-entity" code
        | Error e ->
            Alcotest.failf "expected Api_error, got %s"
              (Decode.error_to_string e)
        | Ok _ -> Alcotest.fail "expected Error" );
    ( "an entity carrying \"missing\" decodes to Ok None",
      `Quick,
      fun () ->
        let j =
          `Assoc
            [
              ( "entities",
                `Assoc
                  [
                    ( "Q5",
                      `Assoc [("id", `String "Q5"); ("missing", `String "")] );
                  ] );
            ]
        in
        Check.check_result "entity" (Alcotest.option entity_t) (Ok None)
          (Wikidata.entity_of_json j) );
  ]

let entity_error_tests =
  let check_unexpected name j =
    match Wikidata.entity_of_json j with
    | Error (Decode.Unexpected _) -> ()
    | Error e ->
        Alcotest.failf "%s: expected Unexpected, got %s" name
          (Decode.error_to_string e)
    | Ok _ -> Alcotest.failf "%s: expected Error" name
  in
  let check_path name expected j =
    match Wikidata.entity_of_json j with
    | Error (Decode.Unexpected {path; _}) ->
        Alcotest.(check string) name expected path
    | Error e ->
        Alcotest.failf "%s: expected Unexpected, got %s" name
          (Decode.error_to_string e)
    | Ok _ -> Alcotest.failf "%s: expected Error" name
  in
  [
    ( "no entities object is Unexpected",
      `Quick,
      fun () -> check_unexpected "no entities" (`Assoc []) );
    ( "an empty entities object is Unexpected at /entities",
      `Quick,
      fun () ->
        check_path "empty entities" "/entities"
          (`Assoc [("entities", `Assoc [])]) );
    ( "a root error that is not an object with a code is Unexpected at /error",
      `Quick,
      fun () ->
        List.iter
          (fun error ->
            check_path "error" "/error" (`Assoc [("error", error)]);
            match Wikidata.search_of_json (`Assoc [("error", error)]) with
            | Error (Decode.Unexpected {path = "/error"; _}) -> ()
            | _ -> Alcotest.fail "search: expected Unexpected at /error")
          [`String "boom"; `List [`Int 1]; `Assoc []] );
    ( "an entity whose id is not a Qid is Unexpected",
      `Quick,
      fun () ->
        check_unexpected "property id"
          (`Assoc
             [("entities", `Assoc [("P846", `Assoc [("id", `String "P846")])])])
    );
  ]

let claim_snak ?(snaktype = "value") ?datavalue () =
  `Assoc
    (("snaktype", `String snaktype)
    ::
    (match datavalue with
    | None -> []
    | Some v -> [("datavalue", `Assoc [("value", v)])]))

let statement ?(rank = "normal") ?(snaktype = "value") ?datavalue () =
  `Assoc
    [("mainsnak", claim_snak ~snaktype ?datavalue ()); ("rank", `String rank)]

let entity_with_p846 statements =
  `Assoc
    [
      ( "entities",
        `Assoc
          [
            ( "Q1",
              `Assoc
                [
                  ("id", `String "Q1");
                  ("claims", `Assoc [("P846", `List statements)]);
                  ("sitelinks", `Assoc []);
                ] );
          ] );
    ]

let entity_qid j =
  match Wikidata.entity_of_json j with
  | Ok (Some e) -> Ok (Qid.to_string e.qid)
  | Ok None -> Error "entity missing"
  | Error e -> Error (Decode.error_to_string e)

let gbif_key_of j =
  match Wikidata.entity_of_json j with
  | Ok (Some e) -> Ok e.gbif_key
  | Ok None -> Error "entity missing"
  | Error e -> Error (Decode.error_to_string e)

let claim_tests =
  [
    ( "a deprecated statement is ignored in favour of the normal one",
      `Quick,
      fun () ->
        let j =
          entity_with_p846
            [
              statement ~rank:"deprecated" ~datavalue:(`String "111") ();
              statement ~rank:"normal" ~datavalue:(`String "222") ();
            ]
        in
        Alcotest.(check (result (option int) string))
          "gbif_key" (Ok (Some 222)) (gbif_key_of j) );
    ( "a preferred statement after a normal one wins",
      `Quick,
      fun () ->
        let j =
          entity_with_p846
            [
              statement ~rank:"normal" ~datavalue:(`String "333") ();
              statement ~rank:"preferred" ~datavalue:(`String "444") ();
            ]
        in
        Alcotest.(check (result (option int) string))
          "gbif_key" (Ok (Some 444)) (gbif_key_of j) );
    ( "a non-numeric external id degrades that field to None",
      `Quick,
      fun () ->
        let j = entity_with_p846 [statement ~datavalue:(`String "12a") ()] in
        Alcotest.(check (result (option int) string))
          "gbif_key" (Ok None) (gbif_key_of j) );
    ( "an external id too large for an int degrades that field to None",
      `Quick,
      fun () ->
        let j =
          entity_with_p846
            [statement ~datavalue:(`String "99999999999999999999") ()]
        in
        Alcotest.(check (result (option int) string))
          "gbif_key" (Ok None) (gbif_key_of j) );
    ( "a statement without a rank is ignored",
      `Quick,
      fun () ->
        let j =
          entity_with_p846
            [
              `Assoc [("mainsnak", claim_snak ~datavalue:(`String "111") ())];
              statement ~datavalue:(`String "222") ();
            ]
        in
        Alcotest.(check (result (option int) string))
          "gbif_key" (Ok (Some 222)) (gbif_key_of j) );
    ( "the qid is the entity's own id, whatever was requested",
      `Quick,
      fun () ->
        (* wbgetentities for a redirected Q1 answers under the requested Q1,
           with [id] the target Q2. *)
        let j =
          `Assoc
            [
              ( "entities",
                `Assoc
                  [
                    ( "Q1",
                      `Assoc
                        [
                          ( "redirects",
                            `Assoc
                              [("from", `String "Q1"); ("to", `String "Q2")] );
                          ("id", `String "Q2");
                        ] );
                  ] );
            ]
        in
        Alcotest.(check (result string string)) "qid" (Ok "Q2") (entity_qid j)
    );
    ( "a snaktype of novalue is ignored, not a crash",
      `Quick,
      fun () ->
        let j = entity_with_p846 [statement ~snaktype:"novalue" ()] in
        Alcotest.(check (result (option int) string))
          "gbif_key" (Ok None) (gbif_key_of j) );
  ]

let common_names_claim values =
  `Assoc
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
                      [
                        ( "P1843",
                          `List
                            (List.map
                               (fun (lang, text) ->
                                 statement
                                   ~datavalue:
                                     (`Assoc
                                        [
                                          ("text", `String text);
                                          ("language", `String lang);
                                        ])
                                   ())
                               values) );
                      ] );
                  ( "sitelinks",
                    `Assoc
                      [
                        ("itwiki", `Assoc [("title", `String "Uno")]);
                        ("frwiki", `Assoc [("title", `String "Un")]);
                      ] );
                ] );
          ] );
    ]

let names_tests =
  [
    ( "every P1843 value is kept in order; sitelinks in fr, en, de, it order, \
       absent ones skipped",
      `Quick,
      fun () ->
        match
          Wikidata.entity_of_json
            (common_names_claim [("fr", "Un"); ("de", "Eins"); ("fr", "Une")])
        with
        | Ok (Some e) ->
            Alcotest.(check (list (pair string string)))
              "common_names"
              [("fr", "Un"); ("de", "Eins"); ("fr", "Une")]
              (List.map
                 (fun (n : Wikidata.Entity.name) -> (n.lang, n.text))
                 e.common_names);
            Alcotest.(check (list (pair string string)))
              "sitelinks"
              [("fr", "Un"); ("it", "Uno")]
              (List.map
                 (fun (s : Wikidata.Entity.sitelink) -> (s.lang, s.title))
                 e.sitelinks);
            Alcotest.(check (option int)) "gbif_key" None e.gbif_key
        | Ok None -> Alcotest.fail "expected Some"
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
  ]

(* ---------- Property.to_string ---------- *)

let property_tests =
  [
    ( "Property.to_string: every property id",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "Gbif_key" "P846"
          (Wikidata.Property.to_string Wikidata.Property.Gbif_key);
        Alcotest.(check string)
          "Powo" "P5037"
          (Wikidata.Property.to_string Wikidata.Property.Powo);
        Alcotest.(check string)
          "Inat" "P3151"
          (Wikidata.Property.to_string Wikidata.Property.Inat);
        Alcotest.(check string)
          "Taxref" "P3186"
          (Wikidata.Property.to_string Wikidata.Property.Taxref);
        Alcotest.(check string)
          "Tela" "P3105"
          (Wikidata.Property.to_string Wikidata.Property.Tela) );
  ]

let suite =
  ( "wikidata",
    search_tests
    @ entity_tests
    @ entity_error_tests
    @ claim_tests
    @ names_tests
    @ property_tests )
