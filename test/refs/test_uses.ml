(* Herbier_refs.Projection.Uses: wikipedia (the matched section's paragraph)
   and plantuse (the Pl@ntUse fields), over the recorded fixtures. *)

module Uses = Herbier_refs.Projection.Uses
module Wikipedia = Herbier_refs.Sources.Wikipedia
module Plantuse = Herbier_refs.Sources.Plantuse
module Decode = Herbier_refs.Decode
module Source_url = Herbier_refs.Source_url

let article_of name file =
  match Wikipedia.article_of_json (Check.json file) with
  | Ok (Some a) -> a
  | Ok None -> Alcotest.failf "%s: article_of_json gave None" name
  | Error e ->
      Alcotest.failf "%s: decode failed: %s" name (Decode.error_to_string e)

let plantuse_page_of name titles file =
  match Plantuse.answer_of_json (Check.json file) with
  | Error e ->
      Alcotest.failf "%s: decode failed: %s" name (Decode.error_to_string e)
  | Ok a -> (
      match Plantuse.pick ~titles a with
      | Some p -> p
      | None -> Alcotest.failf "%s: pick found nothing" name)

(* ---------- wikipedia ---------- *)

let wikipedia_en_digitalis () =
  let a =
    article_of "en digitalis" "wikipedia_extract_en_Digitalis_purpurea.json"
  in
  match Uses.wikipedia a with
  | Some u ->
      Alcotest.(check string) "section" "Medicinal use" u.section;
      Alcotest.(check string) "lang" "en" u.lang;
      Alcotest.(check bool)
        "paragraph starts with Extracted from the leaves" true
        (String.starts_with ~prefix:"Extracted from the leaves" u.paragraph)
  | None -> Alcotest.fail "wikipedia is None"

let wikipedia_fr_digitalis_is_none () =
  let a =
    article_of "fr digitalis" "wikipedia_extract_fr_Digitalis_purpurea.json"
  in
  Alcotest.(check bool)
    "no matching section" true
    (Option.is_none (Uses.wikipedia a))

let wikipedia_fr_arnica () =
  let a =
    article_of "fr arnica" "wikipedia_extract_fr_Arnica_des_montagnes.json"
  in
  match Uses.wikipedia a with
  | Some u ->
      (* « Usages et propriétés » and « Usages en médecine humaine » have no
         text of their own; under the latter, « Historique » comes last. *)
      Alcotest.(check string) "section" "Phytothérapie" u.section;
      Alcotest.(check string) "lang" "fr" u.lang;
      Alcotest.(check bool)
        "paragraph starts with En médecine traditionnelle" true
        (String.starts_with ~prefix:"En médecine traditionnelle" u.paragraph)
  | None -> Alcotest.fail "wikipedia is None"

let wikipedia_en_urtica_is_none () =
  let a = article_of "en urtica" "wikipedia_extract_en_Urtica_dioica.json" in
  Alcotest.(check bool)
    "no matching section" true
    (Option.is_none (Uses.wikipedia a))

let wikipedia_url_is_the_article () =
  let a =
    article_of "en digitalis" "wikipedia_extract_en_Digitalis_purpurea.json"
  in
  match Uses.wikipedia a with
  | Some u ->
      Alcotest.(check string) "title" "Digitalis purpurea" u.title;
      Alcotest.(check string)
        "url" "https://en.wikipedia.org/wiki/Digitalis_purpurea" u.url
  | None -> Alcotest.fail "wikipedia is None"

let wikipedia_tests =
  [
    ("en Digitalis purpurea: « Medicinal use »", `Quick, wikipedia_en_digitalis);
    ( "fr Digitalis purpurea: no matching section: None",
      `Quick,
      wikipedia_fr_digitalis_is_none );
    ("fr Arnica des montagnes: « Phytothérapie »", `Quick, wikipedia_fr_arnica);
    ( "en Urtica dioica: « Relationship to humans » does not match: None",
      `Quick,
      wikipedia_en_urtica_is_none );
    ( "wikipedia: title and url are the article's",
      `Quick,
      wikipedia_url_is_the_article );
  ]

(* ---------- plantuse ---------- *)

let plantuse_digitalis () =
  let p =
    plantuse_page_of "digitalis" ["Digitalis purpurea"]
      "plantuse_page_digitalis_purpurea.json"
  in
  match Uses.plantuse p with
  | Some u ->
      Alcotest.(check (list string)) "summary" ["médicinal"] u.summary;
      Alcotest.(check bool) "text" true (Option.is_none u.text);
      Alcotest.(check string) "title" "Digitalis purpurea" u.title;
      Alcotest.(check string)
        "url" "https://plantuse.plantnet.org/fr/Digitalis_purpurea" u.url
  | None -> Alcotest.fail "plantuse is None"

let plantuse_arnica_is_none () =
  let p =
    plantuse_page_of "arnica" ["Arnica montana"]
      "plantuse_page_arnica_montana.json"
  in
  Alcotest.(check bool)
    "no box, no prose: plantuse is None" true
    (Option.is_none (Uses.plantuse p))

let plantuse_tests =
  [
    ( "Digitalis: summary [médicinal], url is the plantuse page",
      `Quick,
      plantuse_digitalis );
    ( "Arnica: no box nor prose: plantuse is None",
      `Quick,
      plantuse_arnica_is_none );
  ]

(* The article URL used as href: kept only for https on a Wikipedia host,
   else rebuilt from the lang and title. *)
let href_tests =
  let text = "== Usage ==\n" ^ String.make 45 'x' in
  let case name ~lang ~url ~expected_lang ~expected_url =
    ( name,
      `Quick,
      fun () ->
        match
          Uses.wikipedia {title = "Digitalis purpurea"; lang; url; text}
        with
        | Some u ->
            Alcotest.(check string) "lang" expected_lang u.lang;
            Alcotest.(check string) "url" expected_url u.url
        | None -> Alcotest.fail "wikipedia is None" )
  in
  [
    case "an http url falls back to the built one" ~lang:(Some "en")
      ~url:(Some "http://en.wikipedia.org/wiki/Digitalis_purpurea")
      ~expected_lang:"en"
      ~expected_url:(Source_url.wikipedia ~lang:"en" "Digitalis purpurea");
    case "another host falls back to the built one" ~lang:(Some "en")
      ~url:(Some "https://evil.example/wiki/Digitalis_purpurea")
      ~expected_lang:"en"
      ~expected_url:(Source_url.wikipedia ~lang:"en" "Digitalis purpurea");
    case "no pagelanguage: the lang of a checked url, the url kept" ~lang:None
      ~url:(Some "https://de.wikipedia.org/wiki/Roter_Fingerhut")
      ~expected_lang:"de"
      ~expected_url:"https://de.wikipedia.org/wiki/Roter_Fingerhut";
    case "an invalid lang and no url: fr" ~lang:(Some "zz!") ~url:None
      ~expected_lang:"fr"
      ~expected_url:(Source_url.wikipedia ~lang:"fr" "Digitalis purpurea");
  ]

let suite = ("uses", wikipedia_tests @ href_tests @ plantuse_tests)
