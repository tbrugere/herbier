module Decode = Herbier_refs.Decode
module Tela = Herbier_refs.Sources.Tela
module Payload = Herbier_refs.Payload
module Testable = Herbier_test_support.Testable

let url (r : Herbier_refs.Request.t) = r.url

let source_name (r : Herbier_refs.Request.t) =
  Herbier_domain.Reference.Source.to_string r.source

(* ---------- testables ---------- *)

let name_t = Alcotest.testable Tela.pp_name Tela.equal_name
let taxon_t = Alcotest.testable Tela.pp_taxon Tela.equal_taxon
let baseflor_t = Alcotest.testable Tela.pp_baseflor Tela.equal_baseflor

(* ---------- fixtures ---------- *)

let names_digitalis = Check.json "tela_names_digitalis_purpurea.json"
let names_arnica = Check.json "tela_names_arnica_montana.json"
let names_reynoutria = Check.json "tela_names_reynoutria_japonica.json"
let taxon_digitalis = Check.json "tela_taxon_22437.json"
let taxon_arnica = Check.json "tela_taxon_6646.json"
let taxon_fallopia = Check.json "tela_taxon_55763.json"
let baseflor_digitalis = Check.json "tela_baseflor_22437.json"
let baseflor_arnica = Check.json "tela_baseflor_6646.json"
let baseflor_fallopia = Check.json "tela_baseflor_26478.json"

(* ---------- request URLs, against the recording script ---------- *)

let request_tests =
  [
    ( "names: Digitalis purpurea, query order masque then retour.format",
      `Quick,
      fun () ->
        let r =
          match Tela.names ~name:"Digitalis purpurea" with
          | Some r -> r
          | None -> Alcotest.fail "names: expected Some"
        in
        Alcotest.(check string)
          "url"
          "https://api.tela-botanica.org/service:eflore:0.1/bdtfx/noms?masque=Digitalis%20purpurea&retour.format=min"
          (url r);
        Check.check_recorded "tela_names_digitalis_purpurea.json" r );
    ( "names: a blank (trimmed) name is None",
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "blank" true
          (Option.is_none (Tela.names ~name:"  ")) );
    ( "names: the trimmed name is used",
      `Quick,
      fun () ->
        match Tela.names ~name:"  Arnica montana  " with
        | Some r ->
            Alcotest.(check string)
              "url"
              "https://api.tela-botanica.org/service:eflore:0.1/bdtfx/noms?masque=Arnica%20montana&retour.format=min"
              (url r)
        | None -> Alcotest.fail "expected Some" );
    ( "taxon: nn 22437",
      `Quick,
      fun () ->
        let r = Tela.taxon ~nn:22437 in
        Alcotest.(check string)
          "url"
          "https://api.tela-botanica.org/service:eflore:0.1/bdtfx/taxons/22437"
          (url r);
        Check.check_recorded "tela_taxon_22437.json" r );
    ( "baseflor: nn 22437, the colon is percent-encoded as one path segment",
      `Quick,
      fun () ->
        let r = Tela.baseflor ~nn:22437 in
        Alcotest.(check string)
          "url"
          "https://api.tela-botanica.org/service:eflore:0.1/baseflor/informations/bdtfx.nn%3A22437"
          (url r);
        Check.check_recorded "tela_baseflor_22437.json" r );
    ( "every tela request has source Tela",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "names" "tela"
          (source_name (Fake_net.some "Tela.names" (Tela.names ~name:"X")));
        Alcotest.(check string) "taxon" "tela" (source_name (Tela.taxon ~nn:1));
        Alcotest.(check string)
          "baseflor" "tela"
          (source_name (Tela.baseflor ~nn:1)) );
    ( "the recorded fetch_absent lines match their request",
      `Quick,
      fun () ->
        (match Tela.names ~name:"Victoria amazonica" with
        | Some r ->
            Check.check_recorded ~absent:true
              "tela_names_victoria_amazonica_404.txt" r
        | None -> Alcotest.fail "expected Some");
        Check.check_recorded ~absent:true "tela_baseflor_31960_404.txt"
          (Tela.baseflor ~nn:31960);
        Check.check_fixture_exists "tela_names_victoria_amazonica_404.txt";
        Check.check_fixture_exists "tela_baseflor_31960_404.txt" );
  ]

(* ---------- names_of_json ---------- *)

let names_tests =
  [
    ( "Digitalis purpurea: nn 22437, retenu true",
      `Quick,
      fun () ->
        Check.check_result "names" (Alcotest.list name_t)
          (Ok [{Tela.nn = 22437; nom_sci = "Digitalis purpurea"; retenu = true}])
          (Tela.names_of_json names_digitalis) );
    ( "Reynoutria japonica: nn 55763, retenu false (bdtfx accepts Fallopia \
       japonica instead)",
      `Quick,
      fun () ->
        Check.check_result "names" (Alcotest.list name_t)
          (Ok
             [
               {Tela.nn = 55763; nom_sci = "Reynoutria japonica"; retenu = false};
             ])
          (Tela.names_of_json names_reynoutria) );
    ( "an empty resultat object is Ok []",
      `Quick,
      fun () ->
        Check.check_result "names" (Alcotest.list name_t) (Ok [])
          (Tela.names_of_json (`Assoc [("resultat", `Assoc [])])) );
    ( "an empty resultat array (an empty PHP map) is Ok []",
      `Quick,
      fun () ->
        Check.check_result "names" (Alcotest.list name_t) (Ok [])
          (Tela.names_of_json (`Assoc [("resultat", `List [])])) );
    ( "resultat missing is Unexpected at /resultat",
      `Quick,
      fun () ->
        Check.check_unexpected_path "path" "/resultat"
          (Tela.names_of_json (`Assoc [])) );
    ( "resultat a non-empty array is Unexpected at /resultat",
      `Quick,
      fun () ->
        Check.check_unexpected_path "path" "/resultat"
          (Tela.names_of_json (`Assoc [("resultat", `List [`Int 1])])) );
    ( "an element without nom_sci is dropped",
      `Quick,
      fun () ->
        Check.check_result "names" (Alcotest.list name_t) (Ok [])
          (Tela.names_of_json
             (`Assoc
                [
                  ( "resultat",
                    `Assoc [("1", `Assoc [("retenu", `String "true")])] );
                ])) );
    ( "a non-digit key is dropped",
      `Quick,
      fun () ->
        Check.check_result "names" (Alcotest.list name_t) (Ok [])
          (Tela.names_of_json
             (`Assoc
                [
                  ( "resultat",
                    `Assoc
                      [
                        ( "abc",
                          `Assoc
                            [
                              ("nom_sci", `String "X");
                              ("retenu", `String "true");
                            ] );
                      ] );
                ])) );
    ( "retenu as a JSON bool true is accepted, not only the string \"true\"",
      `Quick,
      fun () ->
        match
          Tela.names_of_json
            (`Assoc
               [
                 ( "resultat",
                   `Assoc
                     [
                       ( "1",
                         `Assoc
                           [("nom_sci", `String "X"); ("retenu", `Bool true)] );
                     ] );
               ])
        with
        | Ok [{retenu; _}] -> Alcotest.(check bool) "retenu" true retenu
        | Ok l -> Alcotest.failf "expected 1 name, got %d" (List.length l)
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
  ]

(* ---------- pick ---------- *)

let pick_tests =
  [
    ( "exact match on the trimmed name",
      `Quick,
      fun () ->
        match Tela.names_of_json names_digitalis with
        | Ok names ->
            Alcotest.(check (option name_t))
              "pick"
              (Some
                 {
                   Tela.nn = 22437;
                   nom_sci = "Digitalis purpurea";
                   retenu = true;
                 })
              (Tela.pick ~name:"  Digitalis purpurea  " names)
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "no matching name is None",
      `Quick,
      fun () ->
        match Tela.names_of_json names_digitalis with
        | Ok names ->
            Alcotest.(check (option name_t))
              "pick" None
              (Tela.pick ~name:"Arnica montana" names)
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "retenu preferred over a non-retenu duplicate, wherever it sits",
      `Quick,
      fun () ->
        let retenu =
          match Tela.names_of_json names_digitalis with
          | Ok [n] -> n
          | Ok l -> Alcotest.failf "expected 1 name, got %d" (List.length l)
          | Error e ->
              Alcotest.failf "decode failed: %s" (Decode.error_to_string e)
        in
        let not_retenu =
          {Tela.nn = 99999; nom_sci = "Digitalis purpurea"; retenu = false}
        in
        Alcotest.(check (option name_t))
          "the retenu one, listed second" (Some retenu)
          (Tela.pick ~name:"Digitalis purpurea" [not_retenu; retenu]);
        Alcotest.(check (option name_t))
          "the retenu one, listed first" (Some retenu)
          (Tela.pick ~name:"Digitalis purpurea" [retenu; not_retenu]) );
    ( "with no retenu entry at all, the first match",
      `Quick,
      fun () ->
        let a = {Tela.nn = 1; nom_sci = "X"; retenu = false} in
        let b = {Tela.nn = 2; nom_sci = "X"; retenu = false} in
        Alcotest.(check (option name_t))
          "first" (Some a)
          (Tela.pick ~name:"X" [a; b]) );
    ( "an empty list is None",
      `Quick,
      fun () ->
        Alcotest.(check (option name_t)) "none" None (Tela.pick ~name:"X" []) );
  ]

(* ---------- taxon_of_json ---------- *)

let taxon_tests =
  [
    ( "Digitalis purpurea (22437): id, cd_nom, presence, statut_origine",
      `Quick,
      fun () ->
        match Tela.taxon_of_json taxon_digitalis with
        | Ok t ->
            Alcotest.(check int) "id" 22437 t.id;
            Alcotest.(check string) "nom_sci" "Digitalis purpurea" t.nom_sci;
            Alcotest.(check (option int)) "cd_nom" (Some 94959) t.cd_nom;
            Alcotest.(check (option string))
              "presence" (Some "Présent") t.presence;
            Alcotest.(check (option string))
              "statut_origine" (Some "Natif (=indigène)") t.statut_origine
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "Arnica montana (6646): cd_nom 83874",
      `Quick,
      fun () ->
        match Tela.taxon_of_json taxon_arnica with
        | Ok t -> Alcotest.(check (option int)) "cd_nom" (Some 83874) t.cd_nom
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "a synonym nn (55763) answers the accepted taxon (26478), cd_nom 97964, \
       no statut_origine",
      `Quick,
      fun () ->
        match Tela.taxon_of_json taxon_fallopia with
        | Ok t ->
            Alcotest.(check int) "id" 26478 t.id;
            Alcotest.(check string) "nom_sci" "Fallopia japonica" t.nom_sci;
            Alcotest.(check (option int)) "cd_nom" (Some 97964) t.cd_nom;
            Alcotest.(check (option string))
              "statut_origine" None t.statut_origine
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "id as a non-digit string is Unexpected at /id",
      `Quick,
      fun () ->
        Check.check_unexpected_path "path" "/id"
          (Tela.taxon_of_json
             (`Assoc [("id", `String "x"); ("nom_sci", `String "X")])) );
    ( "id as a JSON int is accepted",
      `Quick,
      fun () ->
        match
          Tela.taxon_of_json (`Assoc [("id", `Int 1); ("nom_sci", `String "X")])
        with
        | Ok t -> Alcotest.(check int) "id" 1 t.id
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "missing id is Unexpected at /id",
      `Quick,
      fun () ->
        Check.check_unexpected_path "path" "/id"
          (Tela.taxon_of_json (`Assoc [("nom_sci", `String "X")])) );
    ( "missing nom_sci is Unexpected at /nom_sci",
      `Quick,
      fun () ->
        Check.check_unexpected_path "path" "/nom_sci"
          (Tela.taxon_of_json (`Assoc [("id", `Int 1)])) );
    ( "a cd_nom that is not all digits is None",
      `Quick,
      fun () ->
        match
          Tela.taxon_of_json
            (`Assoc
               [
                 ("id", `Int 1);
                 ("nom_sci", `String "X");
                 ("cd_nom", `String "12a");
               ])
        with
        | Ok t -> Alcotest.(check (option int)) "cd_nom" None t.cd_nom
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
  ]

(* ---------- baseflor_of_json ---------- *)

let baseflor_tests =
  [
    ( "Digitalis purpurea (22437): floraison, type_bio (principal label), \
       carac_ecolo, the four ve_* labels",
      `Quick,
      fun () ->
        match Tela.baseflor_of_json baseflor_digitalis with
        | Ok b ->
            Alcotest.(check (option string))
              "floraison" (Some "5-9") b.floraison;
            Alcotest.(check (option string))
              "type_bio" (Some "Hémicryptophytes (>= 1m) bisannuels") b.type_bio;
            Alcotest.(check (option string))
              "carac_ecolo"
              (Some
                 "mégaphorbiaies pionnières de clairières acidophiles \
                  planitiaires-collinéennes")
              b.carac_ecolo;
            Alcotest.(check (option string))
              "chorologie" (Some "méditerranéen-atlantique") b.chorologie;
            Alcotest.(check (option string))
              "lumiere" (Some "hémihéliophiles (10 000 lux)") b.lumiere;
            Alcotest.(check (option string))
              "humidite_edaph"
              (Some "mésohydriques (jamais inondé, feuilles malacophylles)")
              b.humidite_edaph;
            Alcotest.(check (option string))
              "reaction_sol" (Some "acidophiles (4,5<pH<5,0)") b.reaction_sol;
            Alcotest.(check (option string))
              "nutriments_sol" (Some "méso-eutrophiles (≈750 µg N/l)")
              b.nutriments_sol
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "Arnica montana (6646): floraison 6-7",
      `Quick,
      fun () ->
        match Tela.baseflor_of_json baseflor_arnica with
        | Ok b ->
            Alcotest.(check (option string))
              "floraison" (Some "6-7") b.floraison
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "Fallopia japonica (26478): floraison is None (empty string), type_bio \
       is the principal label (there is also a secondaire)",
      `Quick,
      fun () ->
        match Tela.baseflor_of_json baseflor_fallopia with
        | Ok b ->
            Alcotest.(check (option string)) "floraison" None b.floraison;
            Alcotest.(check (option string))
              "type_bio" (Some "Géophytes (>= 1m) à rhizome") b.type_bio
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "no type_bio.detail falls back to type_bio.libelle",
      `Quick,
      fun () ->
        match
          Tela.baseflor_of_json
            (`Assoc
               [
                 ("nom_sci", `String "X");
                 ("type_bio.libelle", `String "Hémicryptophytes ");
               ])
        with
        | Ok b ->
            Alcotest.(check (option string))
              "type_bio" (Some "Hémicryptophytes ") b.type_bio
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "missing nom_sci is Unexpected at /nom_sci",
      `Quick,
      fun () ->
        Check.check_unexpected_path "path" "/nom_sci"
          (Tela.baseflor_of_json (`Assoc [])) );
    ( "a non-object root is Unexpected at the root",
      `Quick,
      fun () ->
        Check.check_unexpected_path "path" "" (Tela.baseflor_of_json (`List []))
    );
  ]

(* ---------- Payload pruning round-trips decoding ---------- *)

let check_prune_preserves_decoding name part value_t decode body =
  Alcotest.(check (result value_t Check.error))
    name (decode body)
    (decode (Payload.prune part body))

let smaller_after_pruning name part body =
  let pruned = Payload.prune part body in
  Alcotest.(check bool)
    (name ^ ": pruned is smaller than the raw body")
    true
    (String.length (Yojson.Safe.to_string pruned)
    < String.length (Yojson.Safe.to_string body))

let prune_tests =
  [
    ( "Tela_names: decode(prune body) = decode body, Digitalis and Reynoutria",
      `Quick,
      fun () ->
        check_prune_preserves_decoding "digitalis" Payload.Tela_names
          (Alcotest.list name_t) Tela.names_of_json names_digitalis;
        check_prune_preserves_decoding "arnica" Payload.Tela_names
          (Alcotest.list name_t) Tela.names_of_json names_arnica;
        check_prune_preserves_decoding "reynoutria" Payload.Tela_names
          (Alcotest.list name_t) Tela.names_of_json names_reynoutria );
    ( "Tela_taxon: decode(prune body) = decode body, and pruned is smaller",
      `Quick,
      fun () ->
        List.iter
          (fun (name, body) ->
            check_prune_preserves_decoding name Payload.Tela_taxon taxon_t
              Tela.taxon_of_json body;
            smaller_after_pruning name Payload.Tela_taxon body)
          [
            ("digitalis", taxon_digitalis);
            ("arnica", taxon_arnica);
            ("fallopia", taxon_fallopia);
          ] );
    ( "Tela_baseflor: decode(prune body) = decode body, and pruned is smaller",
      `Quick,
      fun () ->
        List.iter
          (fun (name, body) ->
            check_prune_preserves_decoding name Payload.Tela_baseflor baseflor_t
              Tela.baseflor_of_json body;
            smaller_after_pruning name Payload.Tela_baseflor body)
          [
            ("digitalis", baseflor_digitalis);
            ("arnica", baseflor_arnica);
            ("fallopia", baseflor_fallopia);
          ] );
    ( "prune on malformed literals never changes the decoded result",
      `Quick,
      fun () ->
        List.iter
          (fun (what, body) ->
            check_prune_preserves_decoding (what ^ ": names") Payload.Tela_names
              (Alcotest.list name_t) Tela.names_of_json body;
            check_prune_preserves_decoding (what ^ ": taxon") Payload.Tela_taxon
              taxon_t Tela.taxon_of_json body;
            check_prune_preserves_decoding (what ^ ": baseflor")
              Payload.Tela_baseflor baseflor_t Tela.baseflor_of_json body)
          [("null", `Null); ("empty object", `Assoc []); ("a list", `List [])]
    );
  ]

let suite =
  ( "tela",
    request_tests
    @ names_tests
    @ pick_tests
    @ taxon_tests
    @ baseflor_tests
    @ prune_tests )
