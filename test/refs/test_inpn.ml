module Decode = Herbier_refs.Decode
module Inpn = Herbier_refs.Sources.Inpn
module Payload = Herbier_refs.Payload
module Testable = Herbier_test_support.Testable

let url (r : Herbier_refs.Request.t) = r.url

let source_name (r : Herbier_refs.Request.t) =
  Herbier_domain.Reference.Source.to_string r.source

(* ---------- testables ---------- *)

let name_t = Alcotest.testable Inpn.pp_name Inpn.equal_name
let status_t = Alcotest.testable Inpn.pp_status Inpn.equal_status

let red_list_entry_t =
  Alcotest.testable Inpn.pp_red_list_entry Inpn.equal_red_list_entry

let article_t = Alcotest.testable Inpn.pp_article Inpn.equal_article

(* ---------- fixtures ---------- *)

let name_digitalis = Check.json "inpn_name_94959.json"
let name_arnica = Check.json "inpn_name_83874.json"
let name_fallopia = Check.json "inpn_name_97964.json"
let status_digitalis = Check.json "inpn_status_94959.json"
let status_arnica = Check.json "inpn_status_83874.json"
let status_reynoutria = Check.json "inpn_status_117503.json"
let status_fallopia_synonym = Check.json "inpn_status_97964.json"
let red_list_digitalis = Check.json "inpn_red_list_94959.json"
let red_list_arnica = Check.json "inpn_red_list_83874.json"
let red_list_reynoutria = Check.json "inpn_red_list_117503.json"
let protections_digitalis = Check.json "inpn_protections_94959.json"
let protections_arnica = Check.json "inpn_protections_83874.json"
let protections_reynoutria = Check.json "inpn_protections_117503.json"

(* ---------- request URLs, against the recording script ---------- *)

let request_tests =
  [
    ( "base and metropolitan_france",
      `Quick,
      fun () ->
        Alcotest.(check string) "base" "https://odata-inpn.mnhn.fr" Inpn.base;
        Alcotest.(check string)
          "metropolitan_france" "TERFXFR" Inpn.metropolitan_france );
    ( "name: cd_nom 94959",
      `Quick,
      fun () ->
        let r = Inpn.name ~cd_nom:94959 in
        Alcotest.(check string)
          "url" "https://odata-inpn.mnhn.fr/taxa/names/94959" (url r);
        Check.check_recorded "inpn_name_94959.json" r );
    ( "status: cd_ref 94959",
      `Quick,
      fun () ->
        let r = Inpn.status ~cd_ref:94959 in
        Alcotest.(check string)
          "url"
          "https://odata-inpn.mnhn.fr/taxa/94959/biogeographicStatuses?locationId=TERFXFR"
          (url r);
        Check.check_recorded "inpn_status_94959.json" r );
    ( "red_list: cd_ref 94959",
      `Quick,
      fun () ->
        let r = Inpn.red_list ~cd_ref:94959 in
        Alcotest.(check string)
          "url"
          "https://odata-inpn.mnhn.fr/taxa/redLists/entries?taxrefId=94959&scopes=NATIONAL&scopeLocationId=TERFXFR"
          (url r);
        Check.check_recorded "inpn_red_list_94959.json" r );
    ( "protections: cd_ref 94959",
      `Quick,
      fun () ->
        let r = Inpn.protections ~cd_ref:94959 in
        Alcotest.(check string)
          "url"
          "https://odata-inpn.mnhn.fr/taxa/protections/articles?taxrefIds=94959&embed=SCOPE_LOCATION&size=100"
          (url r);
        Check.check_recorded "inpn_protections_94959.json" r );
    ( "every inpn request has source Taxref",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "name" "taxref"
          (source_name (Inpn.name ~cd_nom:1));
        Alcotest.(check string)
          "status" "taxref"
          (source_name (Inpn.status ~cd_ref:1));
        Alcotest.(check string)
          "red_list" "taxref"
          (source_name (Inpn.red_list ~cd_ref:1));
        Alcotest.(check string)
          "protections" "taxref"
          (source_name (Inpn.protections ~cd_ref:1)) );
    ( "the recorded fetch_absent line matches its request",
      `Quick,
      fun () ->
        Check.check_recorded ~absent:true "inpn_name_99999999_404.txt"
          (Inpn.name ~cd_nom:99999999);
        Check.check_fixture_exists "inpn_name_99999999_404.txt" );
  ]

(* ---------- name_of_json ---------- *)

let name_tests =
  [
    ( "Digitalis purpurea, a valid taxon: the taxon href points at itself",
      `Quick,
      fun () ->
        Check.check_result "name" name_t
          (Ok {Inpn.taxref_id = 94959; valid = Some true; cd_ref = 94959})
          (Inpn.name_of_json name_digitalis) );
    ( "Arnica montana, a valid taxon",
      `Quick,
      fun () ->
        Check.check_result "name" name_t
          (Ok {Inpn.taxref_id = 83874; valid = Some true; cd_ref = 83874})
          (Inpn.name_of_json name_arnica) );
    ( "Fallopia japonica, a synonym: cd_ref is the valid taxon's id (117503), \
       not 97964",
      `Quick,
      fun () ->
        Check.check_result "name" name_t
          (Ok {Inpn.taxref_id = 97964; valid = Some false; cd_ref = 117503})
          (Inpn.name_of_json name_fallopia) );
    ( "missing taxrefId is Unexpected at /taxrefId",
      `Quick,
      fun () ->
        Check.check_unexpected_path "path" "/taxrefId"
          (Inpn.name_of_json (`Assoc [])) );
    ( "no _links.taxon.href at all: cd_ref falls back to taxrefId",
      `Quick,
      fun () ->
        match Inpn.name_of_json (`Assoc [("taxrefId", `Int 1)]) with
        | Ok n -> Alcotest.(check int) "cd_ref" 1 n.cd_ref
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "a taxon href with no digits after /taxa/: cd_ref falls back to taxrefId",
      `Quick,
      fun () ->
        let j =
          `Assoc
            [
              ("taxrefId", `Int 1);
              ( "_links",
                `Assoc
                  [
                    ( "taxon",
                      `Assoc [("href", `String "http://x/taxa/{?embed}")] );
                  ] );
            ]
        in
        match Inpn.name_of_json j with
        | Ok n -> Alcotest.(check int) "cd_ref" 1 n.cd_ref
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "a non-object root is Unexpected at the root",
      `Quick,
      fun () ->
        Check.check_unexpected_path "path" "" (Inpn.name_of_json (`List [])) );
    ( "a synonym (valid false) without a taxon href is Unexpected: its valid \
       taxon is unknown, never its own id",
      `Quick,
      fun () ->
        Check.check_unexpected_path "path" "/_links/taxon/href"
          (Inpn.name_of_json
             (Fake_net.without ["_links"; "taxon"; "href"] name_fallopia)) );
  ]

(* ---------- status_of_json ---------- *)

let status_tests =
  [
    ( "Digitalis purpurea: PRESENT, simplified PRESENT",
      `Quick,
      fun () ->
        Check.check_result "status" (Alcotest.list status_t)
          (Ok [{Inpn.status = "PRESENT"; simplified = Some "PRESENT"}])
          (Inpn.status_of_json status_digitalis) );
    ( "Reynoutria japonica (the valid taxon 117503): INVASIVE, simplified \
       INTRODUCED",
      `Quick,
      fun () ->
        Check.check_result "status" (Alcotest.list status_t)
          (Ok [{Inpn.status = "INVASIVE"; simplified = Some "INTRODUCED"}])
          (Inpn.status_of_json status_reynoutria) );
    ( "an empty page (Fallopia's synonym cd_nom 97964 has no status): Ok []",
      `Quick,
      fun () ->
        Check.check_result "status" (Alcotest.list status_t) (Ok [])
          (Inpn.status_of_json status_fallopia_synonym) );
    ( "Arnica montana: PRESENT",
      `Quick,
      fun () ->
        Check.check_result "status" (Alcotest.list status_t)
          (Ok [{Inpn.status = "PRESENT"; simplified = Some "PRESENT"}])
          (Inpn.status_of_json status_arnica) );
    ( "an element without a string biogeographicStatus is dropped",
      `Quick,
      fun () ->
        Check.check_result "status" (Alcotest.list status_t) (Ok [])
          (Inpn.status_of_json
             (`Assoc
                [
                  ( "_embedded",
                    `Assoc
                      [
                        ( "biogeographicStatuses",
                          `List [`Assoc [("biogeographicStatus", `Int 1)]] );
                      ] );
                ])) );
    ( "a root that is a list is Unexpected at the root",
      `Quick,
      fun () ->
        Check.check_unexpected_path "path" "" (Inpn.status_of_json (`List []))
    );
    ( "a root that is a string is Unexpected at the root",
      `Quick,
      fun () ->
        Check.check_unexpected_path "path" ""
          (Inpn.status_of_json (`String "x")) );
  ]

(* ---------- red_list_of_json ---------- *)

let red_list_tests =
  [
    ( "Digitalis purpurea: LC, Préoccupation mineure, STABLE",
      `Quick,
      fun () ->
        Check.check_result "red_list"
          (Alcotest.list red_list_entry_t)
          (Ok
             [
               {
                 Inpn.category = "LC";
                 description = Some "Préoccupation mineure";
                 trend = Some "STABLE";
               };
             ])
          (Inpn.red_list_of_json red_list_digitalis) );
    ( "Arnica montana: LC, DECREASING",
      `Quick,
      fun () ->
        match Inpn.red_list_of_json red_list_arnica with
        | Ok [e] ->
            Alcotest.(check string) "category" "LC" e.category;
            Alcotest.(check (option string)) "trend" (Some "DECREASING") e.trend
        | Ok l -> Alcotest.failf "expected 1 entry, got %d" (List.length l)
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "Reynoutria japonica (117503): NA, no trend",
      `Quick,
      fun () ->
        match Inpn.red_list_of_json red_list_reynoutria with
        | Ok [e] ->
            Alcotest.(check string) "category" "NA" e.category;
            Alcotest.(check (option string)) "trend" None e.trend
        | Ok l -> Alcotest.failf "expected 1 entry, got %d" (List.length l)
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "an empty page is Ok []",
      `Quick,
      fun () ->
        Check.check_result "red_list"
          (Alcotest.list red_list_entry_t)
          (Ok [])
          (Inpn.red_list_of_json (`Assoc [("page", `Assoc [("size", `Int 0)])]))
    );
    ( "a root that is not an object is Unexpected at the root",
      `Quick,
      fun () ->
        Check.check_unexpected_path "path" "" (Inpn.red_list_of_json (`List []))
    );
  ]

(* ---------- protections_of_json ---------- *)

let protections_tests =
  [
    ( "a page of 17 whose array was renamed is Unexpected, not Ok []",
      `Quick,
      fun () ->
        Check.check_unexpected_path "path" "/_embedded/protectionArticles"
          (Inpn.protections_of_json
             (Fake_net.without
                ["_embedded"; "protectionArticles"]
                protections_arnica)) );
    ( "a page of 17 without _embedded is Unexpected, not Ok []",
      `Quick,
      fun () ->
        Check.check_unexpected_path "path" "/_embedded/protectionArticles"
          (Inpn.protections_of_json
             (Fake_net.without ["_embedded"] protections_arnica)) );
    ( "a page of 17 whose elements all lost their fields is Unexpected",
      `Quick,
      fun () ->
        let renamed =
          match protections_arnica with
          | `Assoc kvs ->
              `Assoc
                (List.map
                   (fun (k, v) ->
                     match k with
                     | "_embedded" ->
                         ( k,
                           `Assoc
                             [
                               ( "protectionArticles",
                                 `List [`Assoc [("portee", `String "x")]] );
                             ] )
                     | _ -> (k, v))
                   kvs)
          | _ -> Alcotest.fail "protections_arnica: not an object"
        in
        Check.check_unexpected_path "path" "/_embedded/protectionArticles"
          (Inpn.protections_of_json renamed) );
    ( "Arnica montana (83874): 17 articles, at least one REGIONAL PROTECTION \
       article located in Centre-Val de Loire",
      `Quick,
      fun () ->
        match Inpn.protections_of_json protections_arnica with
        | Ok articles ->
            Alcotest.(check int) "count" 17 (List.length articles);
            let has_centre =
              List.exists
                (fun (a : Inpn.article) ->
                  String.equal a.scope "REGIONAL"
                  && String.equal a.kind "PROTECTION"
                  &&
                  match a.location with
                  | Some {name; _} -> String.equal name "Centre-Val de Loire"
                  | None -> false)
                articles
            in
            Alcotest.(check bool) "Centre-Val de Loire found" true has_centre
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "Digitalis purpurea (94959): one OVERSEAS INTRODUCTION_BAN article, \
       overseas location",
      `Quick,
      fun () ->
        match Inpn.protections_of_json protections_digitalis with
        | Ok [a] -> (
            Alcotest.(check string) "scope" "OVERSEAS" a.scope;
            Alcotest.(check string) "kind" "INTRODUCTION_BAN" a.kind;
            match a.location with
            | Some {name; overseas; _} ->
                Alcotest.(check string) "name" "Saint-Pierre-et-Miquelon" name;
                Alcotest.(check (option bool)) "overseas" (Some true) overseas
            | None -> Alcotest.fail "no location")
        | Ok l -> Alcotest.failf "expected 1 article, got %d" (List.length l)
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "Reynoutria japonica (117503, the valid taxon): no articles at all",
      `Quick,
      fun () ->
        Check.check_result "protections" (Alcotest.list article_t) (Ok [])
          (Inpn.protections_of_json protections_reynoutria) );
    ( "an element without a string scope and type is dropped",
      `Quick,
      fun () ->
        Check.check_result "protections" (Alcotest.list article_t) (Ok [])
          (Inpn.protections_of_json
             (`Assoc
                [
                  ( "_embedded",
                    `Assoc
                      [
                        ( "protectionArticles",
                          `List [`Assoc [("category", `String "x")]] );
                      ] );
                ])) );
    ( "a root that is a string is Unexpected at the root",
      `Quick,
      fun () ->
        Check.check_unexpected_path "path" ""
          (Inpn.protections_of_json (`String "x")) );
  ]

(* ---------- Payload pruning round-trips decoding ---------- *)

let check_prune_preserves_decoding name part value_t decode body =
  Alcotest.(check (result value_t Check.error))
    name (decode body)
    (decode (Payload.prune part body))

let prune_tests =
  [
    ( "Inpn_name: decode(prune body) = decode body",
      `Quick,
      fun () ->
        List.iter
          (fun (what, body) ->
            check_prune_preserves_decoding what Payload.Inpn_name name_t
              Inpn.name_of_json body)
          [
            ("digitalis", name_digitalis);
            ("arnica", name_arnica);
            ("fallopia", name_fallopia);
          ] );
    ( "Inpn_status: decode(prune body) = decode body",
      `Quick,
      fun () ->
        List.iter
          (fun (what, body) ->
            check_prune_preserves_decoding what Payload.Inpn_status
              (Alcotest.list status_t) Inpn.status_of_json body)
          [
            ("digitalis", status_digitalis);
            ("reynoutria", status_reynoutria);
            ("empty page", status_fallopia_synonym);
          ] );
    ( "Inpn_red_list: decode(prune body) = decode body",
      `Quick,
      fun () ->
        List.iter
          (fun (what, body) ->
            check_prune_preserves_decoding what Payload.Inpn_red_list
              (Alcotest.list red_list_entry_t)
              Inpn.red_list_of_json body)
          [
            ("digitalis", red_list_digitalis);
            ("reynoutria", red_list_reynoutria);
          ] );
    ( "Inpn_protections: decode(prune body) = decode body, and pruned is \
       smaller for a large article list",
      `Quick,
      fun () ->
        List.iter
          (fun (what, body) ->
            check_prune_preserves_decoding what Payload.Inpn_protections
              (Alcotest.list article_t) Inpn.protections_of_json body)
          [("digitalis", protections_digitalis); ("arnica", protections_arnica)];
        let pruned =
          Payload.prune Payload.Inpn_protections protections_arnica
        in
        Alcotest.(check bool)
          "pruned is smaller (the 17-article Arnica body)" true
          (String.length (Yojson.Safe.to_string pruned)
          < String.length (Yojson.Safe.to_string protections_arnica)) );
    ( "prune on malformed literals never changes the decoded result",
      `Quick,
      fun () ->
        List.iter
          (fun (what, body) ->
            check_prune_preserves_decoding (what ^ ": name") Payload.Inpn_name
              name_t Inpn.name_of_json body;
            check_prune_preserves_decoding (what ^ ": status")
              Payload.Inpn_status (Alcotest.list status_t) Inpn.status_of_json
              body;
            check_prune_preserves_decoding (what ^ ": red_list")
              Payload.Inpn_red_list
              (Alcotest.list red_list_entry_t)
              Inpn.red_list_of_json body;
            check_prune_preserves_decoding (what ^ ": protections")
              Payload.Inpn_protections (Alcotest.list article_t)
              Inpn.protections_of_json body)
          [("null", `Null); ("empty object", `Assoc []); ("a list", `List [])]
    );
  ]

let suite =
  ( "inpn",
    request_tests
    @ name_tests
    @ status_tests
    @ red_list_tests
    @ protections_tests
    @ prune_tests )
