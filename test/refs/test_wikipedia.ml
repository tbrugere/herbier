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

let suite = ("wikipedia", fixture_tests @ inline_tests)
