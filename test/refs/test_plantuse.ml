(* Herbier_refs.Sources.Plantuse: titles, page (the request), answer_of_json,
   pick, uses (summary bullets + the "Usages" prose), over the recorded
   plantuse_page_* fixtures. *)

module Plantuse = Herbier_refs.Sources.Plantuse
module Decode = Herbier_refs.Decode
module Text = Herbier_test_support.Text

(* ---------- titles ---------- *)

let titles_tests =
  [
    ( "a binomial gives one title",
      `Quick,
      fun () ->
        Alcotest.(check (list string))
          "titles" ["Digitalis purpurea"]
          (Plantuse.titles "Digitalis purpurea") );
    ( "a name with more than two words also gives its first two",
      `Quick,
      fun () ->
        Alcotest.(check (list string))
          "titles"
          ["Digitalis purpurea subsp. purpurea"; "Digitalis purpurea"]
          (Plantuse.titles "Digitalis purpurea subsp. purpurea") );
    ( "a blank name gives []",
      `Quick,
      fun () ->
        Alcotest.(check (list string)) "titles" [] (Plantuse.titles "  ") );
  ]

(* ---------- page (the request) ---------- *)

let page_tests =
  [
    ( "page url matches the recording script's line, one fixture each",
      `Quick,
      fun () ->
        List.iter
          (fun (file, titles) ->
            match Plantuse.page ~titles with
            | Some r -> Check.check_recorded file r
            | None -> Alcotest.failf "%s: page gave None" file)
          [
            ("plantuse_page_digitalis_purpurea.json", ["Digitalis purpurea"]);
            ("plantuse_page_arnica_montana.json", ["Arnica montana"]);
            ("plantuse_page_fallopia_japonica.json", ["Fallopia japonica"]);
            ("plantuse_page_urtica_dioica.json", ["Urtica dioica"]);
            ("plantuse_page_quercus_robur.json", ["Quercus robur"]);
            ("plantuse_page_polygonum_cuspidatum.json", ["Polygonum cuspidatum"]);
            ( "plantuse_page_digitalis_purpurea_subsp_purpurea.json",
              ["Digitalis purpurea subsp. purpurea"; "Digitalis purpurea"] );
          ] );
    ( "page is None when no title is left",
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "[]" true
          (Option.is_none (Plantuse.page ~titles:[]));
        Alcotest.(check bool)
          "[\" \"]" true
          (Option.is_none (Plantuse.page ~titles:[" "])) );
  ]

(* ---------- answer_of_json, pick ---------- *)

let digitalis = Check.json "plantuse_page_digitalis_purpurea.json"
let arnica = Check.json "plantuse_page_arnica_montana.json"
let fallopia = Check.json "plantuse_page_fallopia_japonica.json"
let polygonum = Check.json "plantuse_page_polygonum_cuspidatum.json"
let urtica = Check.json "plantuse_page_urtica_dioica.json"
let quercus = Check.json "plantuse_page_quercus_robur.json"

let subsp_purpurea =
  Check.json "plantuse_page_digitalis_purpurea_subsp_purpurea.json"

let decode_or_fail name j =
  match Plantuse.answer_of_json j with
  | Ok a -> a
  | Error e ->
      Alcotest.failf "%s: decode failed: %s" name (Decode.error_to_string e)

let pick_title name titles json =
  match Plantuse.pick ~titles (decode_or_fail name json) with
  | Some (p : Plantuse.page) -> Some p.title
  | None -> None

let answer_pick_tests =
  [
    ( "Digitalis: pick finds the page, title as given",
      `Quick,
      fun () ->
        Alcotest.(check (option string))
          "title" (Some "Digitalis purpurea")
          (pick_title "digitalis" ["Digitalis purpurea"] digitalis) );
    ( "Fallopia: missing page, pick is None",
      `Quick,
      fun () ->
        Alcotest.(check (option string))
          "title" None
          (pick_title "fallopia" ["Fallopia japonica"] fallopia) );
    ( "Polygonum cuspidatum: redirected to Reynoutria japonica",
      `Quick,
      fun () ->
        Alcotest.(check (option string))
          "title" (Some "Reynoutria japonica")
          (pick_title "polygonum" ["Polygonum cuspidatum"] polygonum) );
    ( "Digitalis purpurea subsp. purpurea: first title missing, second found",
      `Quick,
      fun () ->
        Alcotest.(check (option string))
          "title" (Some "Digitalis purpurea")
          (pick_title "subsp"
             ["Digitalis purpurea subsp. purpurea"; "Digitalis purpurea"]
             subsp_purpurea) );
    ( "a root error object is Api_error",
      `Quick,
      fun () ->
        match
          Plantuse.answer_of_json
            (`Assoc
               [
                 ("error", `Assoc [("code", `String "x"); ("info", `String "y")]);
               ])
        with
        | Error (Decode.Api_error _) -> ()
        | Error e ->
            Alcotest.failf "expected Api_error, got %s"
              (Decode.error_to_string e)
        | Ok _ -> Alcotest.fail "expected Error" );
    ( "an empty object is Unexpected at /query",
      `Quick,
      fun () ->
        match Plantuse.answer_of_json (`Assoc []) with
        | Error (Decode.Unexpected {path; _}) ->
            Alcotest.(check string) "path" "/query" path
        | Error e ->
            Alcotest.failf "expected Unexpected, got %s"
              (Decode.error_to_string e)
        | Ok _ -> Alcotest.fail "expected Error" );
  ]

(* ---------- uses ---------- *)

let page_of name titles json =
  match Plantuse.pick ~titles (decode_or_fail name json) with
  | Some p -> p
  | None -> Alcotest.failf "%s: pick found nothing" name

let uses_of name titles json = Plantuse.uses (page_of name titles json)

let uses_tests =
  [
    ( "Digitalis: summary [médicinal], no Usages prose",
      `Quick,
      fun () ->
        let u = uses_of "digitalis" ["Digitalis purpurea"] digitalis in
        Alcotest.(check (list string)) "summary" ["médicinal"] u.summary;
        Alcotest.(check bool) "text" true (Option.is_none u.text) );
    ( "Arnica: no box, no prose: [] and None",
      `Quick,
      fun () ->
        let u = uses_of "arnica" ["Arnica montana"] arnica in
        Alcotest.(check (list string)) "summary" [] u.summary;
        Alcotest.(check bool) "text" true (Option.is_none u.text) );
    ( "Urtica: the four bullets in order, text starts with the La médecine \
       populaire sentence",
      `Quick,
      fun () ->
        let u = uses_of "urtica" ["Urtica dioica"] urtica in
        Alcotest.(check (list string))
          "summary"
          [
            "jeunes feuilles consommées comme légume ou en soupe";
            "feuilles utilisées pour emballer des aliments";
            "fibres des tiges textiles";
            "médicinale";
          ]
          u.summary;
        match u.text with
        | Some t ->
            Alcotest.(check bool)
              "starts with the prose" true
              (String.starts_with
                 ~prefix:"La médecine populaire utilise les « orties »" t)
        | None -> Alcotest.fail "text is None" );
    ( "Quercus: 12 bullets, text is French prose, never the English Citation \
       encadré quote",
      `Quick,
      fun () ->
        let u = uses_of "quercus" ["Quercus robur"] quercus in
        Alcotest.(check int) "12 bullets" 12 (List.length u.summary);
        Alcotest.(check (option string))
          "text"
          (Some
             "Le bois de chêne est utilisé pour la construction de bâtiments \
              et de meubles. Les glands sont utilisées dans l'alimentation \
              humaine et animale.")
          u.text );
  ]

(* ---------- find, unreadable pages, table cells ---------- *)

(* The recorded Urtica answer with its page's revisions removed, as MediaWiki
   answers for a hidden revision. *)
let without_revisions json =
  let drop = function
    | `Assoc fields -> `Assoc (List.remove_assoc "revisions" fields)
    | other -> other
  in
  let pages = function
    | `Assoc fields ->
        `Assoc
          (List.map
             (function
               | "pages", `List ps -> ("pages", `List (List.map drop ps))
               | field -> field)
             fields)
    | other -> other
  in
  match json with
  | `Assoc fields ->
      `Assoc
        (List.map
           (function "query", q -> ("query", pages q) | field -> field)
           fields)
  | other -> other

(* A literal page with one « Usages » section. *)
let usages body : Plantuse.page =
  {title = "T"; wikitext = "== Usages ==\n" ^ body ^ "\n"}

let more_tests =
  [
    ( "find: the subspecies' binomial, as pick with titles",
      `Quick,
      fun () ->
        Alcotest.(check (option string))
          "title" (Some "Digitalis purpurea")
          (Option.map
             (fun (p : Plantuse.page) -> p.title)
             (Plantuse.find ~name:(Some "Digitalis purpurea subsp. purpurea")
                (decode_or_fail "subsp" subsp_purpurea))) );
    ( "find: no name, no page",
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "None" true
          (Option.is_none
             (Plantuse.find ~name:None (decode_or_fail "urtica" urtica))) );
    ( "a page that exists without revisions is Unexpected at its content",
      `Quick,
      fun () ->
        Check.check_unexpected_path "path"
          "/query/pages/0/revisions/0/slots/main/content"
          (Plantuse.answer_of_json (without_revisions urtica)) );
    ( "a table cell's attributes are dropped",
      `Quick,
      fun () ->
        Alcotest.(check (option string))
          "text" (Some "Les feuilles se mangent.")
          (Plantuse.uses
             (usages "{|\n| style=\"width:50%\" | Les feuilles se mangent.\n|}"))
            .text );
    ( "inline cells (||) are joined, links inside kept",
      `Quick,
      fun () ->
        Alcotest.(check (option string))
          "text" (Some "Les feuilles se mangent. Les tiges donnent des fibres.")
          (Plantuse.uses
             (usages
                "{|\n\
                 |Les feuilles se mangent. || Les [[tige|tiges]] donnent des \
                 fibres.\n\
                 |}"))
            .text );
    ( "a simple cell keeps its text",
      `Quick,
      fun () ->
        Alcotest.(check (option string))
          "text" (Some "Les feuilles se mangent.")
          (Plantuse.uses (usages "{|\n|Les feuilles se mangent.\n|}")).text );
  ]

let suite =
  ( "plantuse",
    titles_tests @ page_tests @ answer_pick_tests @ uses_tests @ more_tests )
