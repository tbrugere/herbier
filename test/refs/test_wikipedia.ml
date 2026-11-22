module Decode = Herbier_refs.Decode
module Qid = Herbier_refs.Qid
module Wikipedia = Herbier_refs.Sources.Wikipedia

let fr_digitalis = Check.json "wikipedia_summary_fr_Digitalis_purpurea.json"
let fr_arnica = Check.json "wikipedia_summary_fr_Arnica_montana.json"
let en_digitalis = Check.json "wikipedia_summary_en_Digitalis_purpurea.json"
let fr_lis = Check.json "wikipedia_summary_fr_Lis.json"

let kind =
  Alcotest.testable
    (fun f (k : Wikipedia.kind) ->
      Format.pp_print_string f
        (match k with
        | Standard -> "Standard"
        | Disambiguation -> "Disambiguation"
        | Other s -> "Other " ^ s))
    ( = )

let qid name = Alcotest.(check (option string)) name

let decode_or_fail name j =
  match Wikipedia.summary_of_json j with
  | Ok t -> t
  | Error e ->
      Alcotest.failf "%s: decode failed: %s" name (Decode.error_to_string e)

let fixture_tests =
  [
    ( "fr Digitalis purpurea: standard page, every field",
      `Quick,
      fun () ->
        let t = decode_or_fail "fr_digitalis" fr_digitalis in
        Alcotest.check kind "kind" Wikipedia.Standard t.kind;
        Alcotest.(check string) "title" "Digitalis purpurea" t.title;
        Alcotest.(check (option string)) "lang" (Some "fr") t.lang;
        qid "wikibase_item" (Some "Q157555")
          (Option.map Qid.to_string t.wikibase_item);
        Alcotest.(check (option string))
          "page_url" (Some "https://fr.wikipedia.org/wiki/Digitalis_purpurea")
          t.page_url;
        Alcotest.(check bool)
          "extract starts with the title" true
          (match t.extract with
          | Some e -> String.starts_with ~prefix:"Digitalis purpurea" e
          | None -> false);
        Alcotest.(check (option string))
          "description"
          (Some "plante extrêmement toxique dont est extraite la digitaline")
          t.description;
        Alcotest.(check (option (triple string int int)))
          "thumbnail"
          (Some
             ( "https://thumb.wikimedia.org/wikipedia/commons/thumb/4/48/Digitalis_purpurea_Koehler_drawing.jpg/330px-Digitalis_purpurea_Koehler_drawing.jpg?utm_source=fr.wikipedia.org&utm_campaign=api&utm_content=thumbnail",
               330,
               411 ))
          (Option.map
             (fun (th : Wikipedia.thumbnail) ->
               (th.source, th.width, th.height))
             t.thumbnail) );
    ( "fr Arnica montana: redirected title, its own wikibase item",
      `Quick,
      fun () ->
        let t = decode_or_fail "fr_arnica" fr_arnica in
        Alcotest.(check string) "title" "Arnica des montagnes" t.title;
        qid "wikibase_item" (Some "Q207848")
          (Option.map Qid.to_string t.wikibase_item) );
    ( "en Digitalis purpurea: lang en, same wikibase item as fr",
      `Quick,
      fun () ->
        let t = decode_or_fail "en_digitalis" en_digitalis in
        Alcotest.(check (option string)) "lang" (Some "en") t.lang;
        qid "wikibase_item" (Some "Q157555")
          (Option.map Qid.to_string t.wikibase_item) );
    ( "fr Lis: a disambiguation page",
      `Quick,
      fun () ->
        let t = decode_or_fail "fr_lis" fr_lis in
        Alcotest.check kind "kind" Wikipedia.Disambiguation t.kind;
        qid "wikibase_item" (Some "Q351749")
          (Option.map Qid.to_string t.wikibase_item) );
  ]

let inline_tests =
  [
    ( "an unknown type is Other, every optional field is None",
      `Quick,
      fun () ->
        let j =
          `Assoc [("type", `String "no-extract"); ("title", `String "X")]
        in
        let t = decode_or_fail "no-extract" j in
        Alcotest.check kind "kind" (Wikipedia.Other "no-extract") t.kind;
        Alcotest.(check string) "title" "X" t.title;
        Alcotest.(check (option string)) "lang" None t.lang;
        Alcotest.(check (option string)) "description" None t.description;
        Alcotest.(check (option string)) "extract" None t.extract;
        Alcotest.(check (option string)) "page_url" None t.page_url;
        Alcotest.(check bool)
          "wikibase_item" true
          (Option.is_none t.wikibase_item);
        Alcotest.(check bool) "thumbnail" true (Option.is_none t.thumbnail) );
    ( "a missing title is Unexpected at /title",
      `Quick,
      fun () ->
        match
          Wikipedia.summary_of_json (`Assoc [("type", `String "standard")])
        with
        | Error (Decode.Unexpected {path; _}) ->
            Alcotest.(check string) "path" "/title" path
        | Error e ->
            Alcotest.failf "expected Unexpected, got %s"
              (Decode.error_to_string e)
        | Ok _ -> Alcotest.fail "expected Error" );
    ( "a full thumbnail and the optional strings are decoded",
      `Quick,
      fun () ->
        let j =
          `Assoc
            [
              ("type", `String "standard");
              ("title", `String "X y");
              ("lang", `String "fr");
              ("description", `String "espèce de plantes");
              ("wikibase_item", `String "Q1");
              ( "content_urls",
                `Assoc [("desktop", `Assoc [("page", `String "https://w/X_y")])]
              );
              ( "thumbnail",
                `Assoc
                  [
                    ("source", `String "https://x/y.jpg");
                    ("width", `Int 20);
                    ("height", `Int 10);
                  ] );
            ]
        in
        let t = decode_or_fail "full" j in
        Alcotest.(check string) "title" "X y" t.title;
        Alcotest.(check (option string))
          "description" (Some "espèce de plantes") t.description;
        Alcotest.(check (option string))
          "page_url" (Some "https://w/X_y") t.page_url;
        Alcotest.(check (option (triple string int int)))
          "thumbnail"
          (Some ("https://x/y.jpg", 20, 10))
          (Option.map
             (fun (th : Wikipedia.thumbnail) ->
               (th.source, th.width, th.height))
             t.thumbnail) );
    ( "a wikibase_item that is not a Qid is None",
      `Quick,
      fun () ->
        let t =
          decode_or_fail "bad qid"
            (`Assoc
               [
                 ("type", `String "standard");
                 ("title", `String "X");
                 ("wikibase_item", `String "P1");
               ])
        in
        Alcotest.(check bool)
          "wikibase_item" true
          (Option.is_none t.wikibase_item) );
    ( "a missing type is Unexpected at /type",
      `Quick,
      fun () ->
        match Wikipedia.summary_of_json (`Assoc [("title", `String "X")]) with
        | Error (Decode.Unexpected {path; _}) ->
            Alcotest.(check string) "path" "/type" path
        | Error e ->
            Alcotest.failf "expected Unexpected, got %s"
              (Decode.error_to_string e)
        | Ok _ -> Alcotest.fail "expected Error" );
    ( "a thumbnail missing its width is dropped entirely",
      `Quick,
      fun () ->
        let j =
          `Assoc
            [
              ("type", `String "standard");
              ("title", `String "X");
              ( "thumbnail",
                `Assoc
                  [("source", `String "https://x/y.jpg"); ("height", `Int 10)]
              );
            ]
        in
        let t = decode_or_fail "thumbnail without width" j in
        Alcotest.(check bool) "thumbnail" true (Option.is_none t.thumbnail) );
  ]

(* ---------- extract ---------- *)

let extract_tests =
  [
    ( "extract url matches the recording script's line",
      `Quick,
      fun () ->
        List.iter
          (fun (file, lang, title) ->
            match Wikipedia.extract ~lang ~title with
            | Some r -> Check.check_recorded file r
            | None -> Alcotest.failf "%s: extract gave None" file)
          [
            ( "wikipedia_extract_fr_Digitalis_purpurea.json",
              "fr",
              "Digitalis purpurea" );
            ( "wikipedia_extract_en_Digitalis_purpurea.json",
              "en",
              "Digitalis purpurea" );
            ( "wikipedia_extract_fr_Arnica_des_montagnes.json",
              "fr",
              "Arnica des montagnes" );
            ("wikipedia_extract_en_Arnica_montana.json", "en", "Arnica montana");
            ("wikipedia_extract_en_Urtica_dioica.json", "en", "Urtica dioica");
            ("wikipedia_extract_fr_Xyzzy_foo.json", "fr", "Xyzzy foo");
          ] );
    ( "extract is None for an invalid lang or a blank/./.. title",
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "lang FR" true
          (Option.is_none (Wikipedia.extract ~lang:"FR" ~title:"X"));
        Alcotest.(check bool)
          "blank title" true
          (Option.is_none (Wikipedia.extract ~lang:"fr" ~title:"  ")) );
  ]

(* ---------- article_of_json ---------- *)

let one_page fields =
  `Assoc [("query", `Assoc [("pages", `List [`Assoc fields])])]

let article_tests =
  [
    ( "a missing page is Ok None",
      `Quick,
      fun () ->
        match
          Wikipedia.article_of_json
            (Check.json "wikipedia_extract_fr_Xyzzy_foo.json")
        with
        | Ok None -> ()
        | Ok (Some _) -> Alcotest.fail "expected None"
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "en Digitalis purpurea: lang and url",
      `Quick,
      fun () ->
        match
          Wikipedia.article_of_json
            (Check.json "wikipedia_extract_en_Digitalis_purpurea.json")
        with
        | Ok (Some a) ->
            Alcotest.(check (option string)) "lang" (Some "en") a.lang;
            Alcotest.(check (option string))
              "url" (Some "https://en.wikipedia.org/wiki/Digitalis_purpurea")
              a.url
        | Ok None -> Alcotest.fail "expected Some"
        | Error e ->
            Alcotest.failf "decode failed: %s" (Decode.error_to_string e) );
    ( "a root error object is Api_error",
      `Quick,
      fun () ->
        match
          Wikipedia.article_of_json
            (`Assoc
               [
                 ("error", `Assoc [("code", `String "x"); ("info", `String "y")]);
               ])
        with
        | Error (Decode.Api_error {code; _}) ->
            Alcotest.(check string) "code" "x" code
        | Error e ->
            Alcotest.failf "expected Api_error, got %s"
              (Decode.error_to_string e)
        | Ok _ -> Alcotest.fail "expected Error" );
    ( "no query object is Unexpected at /query",
      `Quick,
      fun () ->
        Check.check_unexpected_path "path" "/query"
          (Wikipedia.article_of_json (`Assoc [])) );
    ( "pages not an array is Unexpected at /query/pages",
      `Quick,
      fun () ->
        Check.check_unexpected_path "path" "/query/pages"
          (Wikipedia.article_of_json
             (`Assoc [("query", `Assoc [("pages", `Assoc [])])])) );
    ( "an empty pages array is Ok None",
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "Ok None" true
          (Wikipedia.article_of_json
             (`Assoc [("query", `Assoc [("pages", `List [])])])
          = Ok None) );
    ( "an invalid page is Ok None",
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "Ok None" true
          (Wikipedia.article_of_json (one_page [("invalid", `Bool true)])
          = Ok None) );
    ( "a page without extract is Unexpected at its extract",
      `Quick,
      fun () ->
        Check.check_unexpected_path "path" "/query/pages/0/extract"
          (Wikipedia.article_of_json (one_page [("title", `String "T")])) );
    ( "a page without title is Unexpected at its title",
      `Quick,
      fun () ->
        Check.check_unexpected_path "path" "/query/pages/0/title"
          (Wikipedia.article_of_json (one_page [("extract", `String "")])) );
  ]

(* ---------- uses_title ---------- *)

let uses_title_cases =
  [
    ("fr", "Usages et propriétés", true);
    ("fr", "Usages en médecine humaine", true);
    ("fr", "Usages en médecine vétérinaire", true);
    ("fr", "Autres usages", true);
    ("fr", "Usages médicinaux", true);
    ("fr", "Utilisation", true);
    ("fr", "Propriétés médicinales", false);
    ("fr", "Constituants", false);
    ("en", "Medicinal use", true);
    ("en", "Use in herbal medicine", true);
    ("en", "Uses", true);
    ("en", "Relationship to humans", false);
    ("en", "Cultivation", false);
    ("en", "User guide", false);
  ]

let uses_title_tests =
  List.map
    (fun (lang, title, expected) ->
      ( Printf.sprintf "uses_title ~lang:%S %S = %b" lang title expected,
        `Quick,
        fun () ->
          Alcotest.(check bool)
            title expected
            (Wikipedia.uses_title ~lang title) ))
    uses_title_cases

(* ---------- uses_line ---------- *)

let uses_line_result (a : Wikipedia.article) =
  Option.map (fun (s, l) -> (s, l)) (Wikipedia.uses_line a)

let article_or_fail name file =
  match Wikipedia.article_of_json (Check.json file) with
  | Ok (Some a) -> a
  | Ok None -> Alcotest.failf "%s: article_of_json gave None" name
  | Error e ->
      Alcotest.failf "%s: decode failed: %s" name (Decode.error_to_string e)

let uses_line_tests =
  [
    ( "fr Digitalis purpurea: no matching section",
      `Quick,
      fun () ->
        let a =
          article_or_fail "fr digitalis"
            "wikipedia_extract_fr_Digitalis_purpurea.json"
        in
        Alcotest.(check bool) "None" true (Option.is_none (uses_line_result a))
    );
    ( "en Digitalis purpurea: Medicinal use, line starts with Extracted from \
       the leaves",
      `Quick,
      fun () ->
        let a =
          article_or_fail "en digitalis"
            "wikipedia_extract_en_Digitalis_purpurea.json"
        in
        match uses_line_result a with
        | Some (section, line) ->
            Alcotest.(check string) "section" "Medicinal use" section;
            Alcotest.(check bool)
              "line" true
              (String.starts_with ~prefix:"Extracted from the leaves" line)
        | None -> Alcotest.fail "expected Some" );
    ( "fr Arnica des montagnes: the uses heading's subsections, Phytothérapie",
      `Quick,
      fun () ->
        let a =
          article_or_fail "fr arnica"
            "wikipedia_extract_fr_Arnica_des_montagnes.json"
        in
        match uses_line_result a with
        | Some (section, line) ->
            Alcotest.(check string) "section" "Phytothérapie" section;
            Alcotest.(check bool)
              "line" true
              (String.starts_with ~prefix:"En médecine traditionnelle" line)
        | None -> Alcotest.fail "expected Some" );
    ( "en Urtica dioica: no matching section (Relationship to humans)",
      `Quick,
      fun () ->
        let a =
          article_or_fail "en urtica" "wikipedia_extract_en_Urtica_dioica.json"
        in
        Alcotest.(check bool) "None" true (Option.is_none (uses_line_result a));
        Alcotest.(check bool) "has_uses false" false (Wikipedia.has_uses a) );
  ]

(* Literal texts: what a uses heading's subsections give. *)
let long = String.make 45 'x'

let fr text : Wikipedia.article =
  {title = "T"; lang = Some "fr"; url = None; text}

let tree_tests =
  let check name expected text =
    ( name,
      `Quick,
      fun () ->
        Alcotest.(check (option (pair string string)))
          "uses_line" expected
          (Wikipedia.uses_line (fr text)) )
  in
  [
    check "own body first"
      (Some ("Usages", "own " ^ long))
      ("== Usages ==\nown " ^ long ^ "\n=== Autres usages ===\nsub " ^ long);
    check "empty body: a uses subsection before an earlier other one"
      (Some ("Usages médicinaux", "med " ^ long))
      ("== Usages ==\n=== Composition ===\nchem "
      ^ long
      ^ "\n=== Usages médicinaux ===\nmed "
      ^ long);
    check "empty body, no uses subsection: the first other one"
      (Some ("Composition", "chem " ^ long))
      ("== Usages ==\n=== Composition ===\nchem "
      ^ long
      ^ "\n=== Cuisine ===\nfood "
      ^ long);
    check "a history subsection comes last"
      (Some ("Phytothérapie", "now " ^ long))
      ("== Usages ==\n=== Historique ===\npast "
      ^ long
      ^ "\n=== Phytothérapie ===\nnow "
      ^ long);
    check "only a history subsection: it is read"
      (Some ("Histoire", "past " ^ long))
      ("== Usages ==\n=== Histoire ===\npast " ^ long);
    check "the next level-2 section is not a subsection" None
      ("== Usages ==\nshort\n== Description ==\ndesc " ^ long);
    check "a uses section nested in another section is found"
      (Some ("Usages", "use " ^ long))
      ("== Plante ==\n=== Usages ===\nuse " ^ long);
    ( "in_uses: a uses section and its subsections, not the next section",
      `Quick,
      fun () ->
        let _lead, sections =
          Herbier_refs.Wiki_text.sections
            "== A ==\n\
             == Usages ==\n\
             === B ===\n\
             ==== C ====\n\
             == D ==\n\
             === Emplois ==="
        in
        Alcotest.(check (list (pair string bool)))
          "in_uses"
          [
            ("A", false);
            ("Usages", true);
            ("B", true);
            ("C", true);
            ("D", false);
            ("Emplois", true);
          ]
          (List.map
             (fun ((s : Herbier_refs.Wiki_text.section), kept) ->
               (s.title, kept))
             (Wikipedia.in_uses ~lang:"fr" sections)) );
  ]

let suite =
  ( "wikipedia",
    fixture_tests
    @ inline_tests
    @ extract_tests
    @ article_tests
    @ uses_title_tests
    @ uses_line_tests
    @ tree_tests )
