(* Herbier_refs.Wiki_text: sections, strip, templates, bullets,
   first_sentences, code_points, over small literal texts and the recorded
   Pl@ntUse / Wikipedia fixtures. *)

module Wiki_text = Herbier_refs.Wiki_text

let section_t = Alcotest.testable Wiki_text.pp_section Wiki_text.equal_section
let sections_t = Alcotest.list section_t
let section ~level ~title ~body : Wiki_text.section = {level; title; body}

(* ---------- sections ---------- *)

let sections_small_literal () =
  let text =
    "Lead text.\n\
     == Usages ==\n\
     Body1 line1\n\
     Body1 line2\n\
     === Sub ===\n\
     Body2\n\
     == Autres ==\n\
     Body3"
  in
  Alcotest.(check (pair string sections_t))
    "lead and three sections, levels and titles as written"
    ( "Lead text.",
      [
        section ~level:2 ~title:"Usages" ~body:"Body1 line1\nBody1 line2";
        section ~level:3 ~title:"Sub" ~body:"Body2";
        section ~level:2 ~title:"Autres" ~body:"Body3";
      ] )
    (Wiki_text.sections text)

let sections_not_headings () =
  let text = "= T =\n== T =\nReal body, not a heading above" in
  Alcotest.(check (pair string sections_t))
    "\"= T =\" (n=1) and \"== T =\" (mismatched) are not headings: the whole \
     text is the lead, no section"
    (text, []) (Wiki_text.sections text)

let sections_crlf () =
  let text = "Lead\r\n== Usages ==\r\nLine1\r\nLine2" in
  Alcotest.(check (pair string sections_t))
    "a trailing '\\r' before '\\n' is dropped from every line"
    ("Lead", [section ~level:2 ~title:"Usages" ~body:"Line1\nLine2"])
    (Wiki_text.sections text)

let sections_no_heading_at_all () =
  let text = "Just a lead\nwith two lines." in
  Alcotest.(check (pair string sections_t))
    "no heading: (whole text, [])" (text, []) (Wiki_text.sections text)

let sections_arnica_extract () =
  let text =
    Check.extract_of_fixture "wikipedia_extract_fr_Arnica_des_montagnes.json"
  in
  let _, sections = Wiki_text.sections text in
  let titles =
    List.filter_map
      (fun (s : Wiki_text.section) ->
        match
          List.mem s.title
            [
              "Usages et propriétés";
              "Constituants";
              "Usages en médecine humaine";
              "Usages en médecine vétérinaire";
              "Autres usages";
            ]
        with
        | true -> Some (s.title, s.level)
        | false -> None)
      sections
  in
  Alcotest.(check (list (pair string int)))
    "the five titles, in document order, with their levels"
    [
      ("Usages et propriétés", 2);
      ("Constituants", 3);
      ("Usages en médecine humaine", 3);
      ("Usages en médecine vétérinaire", 3);
      ("Autres usages", 3);
    ]
    titles

let sections_tests =
  [
    ( "sections: lead and levels/titles of a small literal text",
      `Quick,
      sections_small_literal );
    ( "sections: \"= T =\" and \"== T =\" are not headings",
      `Quick,
      sections_not_headings );
    ("sections: a trailing \\r before \\n is dropped", `Quick, sections_crlf);
    ("sections: no heading gives (text, [])", `Quick, sections_no_heading_at_all);
    ( "sections: the recorded fr Arnica des montagnes extract, five titles in \
       order",
      `Quick,
      sections_arnica_extract );
  ]

(* ---------- strip ---------- *)

let strip_case name input expected =
  ( name,
    `Quick,
    fun () -> Alcotest.(check string) name expected (Wiki_text.strip input) )

let strip_tests =
  [
    strip_case "a <ref>...</ref> is removed"
      "Texte<ref name=\"x\">cite</ref> suite." "Texte suite.";
    strip_case "a self-closing <ref .../> is removed"
      "Texte<ref name=\"x\"/> suite." "Texte suite.";
    strip_case "an HTML comment is removed" "Texte <!-- commentaire --> suite."
      "Texte suite.";
    strip_case "nested templates are removed, innermost included"
      "{{a|{{b|c}}}}reste" "reste";
    strip_case "File:/Fichier:/Catégorie: links are removed"
      "[[File:x.jpg|vignette]] texte [[Catégorie:Plantes]]" "texte";
    strip_case "a piped link keeps the label, a plain one keeps the target"
      "[[Cible|Libellé]] et [[Simple]]" "Libellé et Simple";
    strip_case "an external link with a label keeps the label"
      "voir [http://example.org Label]." "voir Label.";
    strip_case "an external link without a label is removed"
      "voir [http://example.org]." "voir .";
    strip_case "bold and italic markup is removed" "'''Nom''' et ''italique''."
      "Nom et italique.";
    strip_case "any other tag is removed, its content kept"
      "Valeur : <sup>2</sup>." "Valeur : 2.";
    strip_case "entities: nbsp, amp, lt, gt, quot, #39"
      "A&nbsp;B&amp;C&lt;D&gt;E&quot;F&#39;G" "A B&C<D>E\"F'G";
    strip_case "an unclosed {{ keeps the rest of the text as is"
      "avant {{incomplet qui ne se ferme jamais"
      "avant {{incomplet qui ne se ferme jamais";
  ]

(* ---------- templates ---------- *)

let urtica_wikitext =
  Check.wikitext_of_fixture "plantuse_page_urtica_dioica.json"

let template_t = Alcotest.(list (list (pair string string)))

let templates_urtica_encadre () =
  Alcotest.(check template_t)
    "one occurrence, color/titre/texte in document order"
    [
      [
        ("color", "lightgreen");
        ("titre", "Résumé des usages");
        ( "texte",
          "*jeunes feuilles consommées comme légume ou en soupe\n\
           *feuilles utilisées pour emballer des aliments\n\
           *fibres des tiges textiles\n\
           *médicinale" );
      ];
    ]
    (Wiki_text.templates ~name:"Encadré" urtica_wikitext)

let templates_pipe_inside_nesting_does_not_split () =
  let text = "{{Box|titre=T|texte=voir [[Cible|Libellé]] et {{Autre|x|y}}}}" in
  Alcotest.(check template_t)
    "a '|' inside [[a|b]] or a nested {{x|y}} does not split the outer piece"
    [[("titre", "T"); ("texte", "voir [[Cible|Libellé]] et {{Autre|x|y}}")]]
    (Wiki_text.templates ~name:"Box" text)

let templates_tests =
  [
    ( "templates ~name:\"Encadré\" on the recorded Urtica wikitext",
      `Quick,
      templates_urtica_encadre );
    ( "templates: a '|' inside [[...]] or a nested {{...}} does not split",
      `Quick,
      templates_pipe_inside_nesting_does_not_split );
  ]

(* ---------- bullets, first_sentences ---------- *)

let urtica_texte =
  match Wiki_text.templates ~name:"Encadré" urtica_wikitext with
  | [kvs] -> (
      match List.assoc_opt "texte" kvs with
      | Some s -> s
      | None -> Alcotest.fail "no texte parameter")
  | _ -> Alcotest.fail "expected one Encadré occurrence"

let bullets_urtica () =
  Alcotest.(check (list string))
    "the four bullets, stars dropped, in order"
    [
      "jeunes feuilles consommées comme légume ou en soupe";
      "feuilles utilisées pour emballer des aliments";
      "fibres des tiges textiles";
      "médicinale";
    ]
    (Wiki_text.bullets urtica_texte)

let bullets_blank_dropped () =
  Alcotest.(check (list string))
    "a non-* line and a blank * line are both dropped" ["a"; "b"]
    (Wiki_text.bullets "*a\nnot a bullet\n*\n*b")

let first_sentences_cases () =
  let text = "Première phrase. Deuxième phrase ! Troisième phrase?" in
  Alcotest.(check string)
    "n=2: the first two sentences" "Première phrase. Deuxième phrase !"
    (Wiki_text.first_sentences ~n:2 text);
  Alcotest.(check string) "n=0: empty" "" (Wiki_text.first_sentences ~n:0 text);
  Alcotest.(check string)
    "a '.' after a lone capital (author initial) is not a sentence end"
    "Digitalis purpurea L. est toxique."
    (Wiki_text.first_sentences ~n:1
       "Digitalis purpurea L. est toxique. Autre phrase.");
  Alcotest.(check string)
    "fewer sentences than n: the whole trimmed text" "Une seule phrase."
    (Wiki_text.first_sentences ~n:5 "  Une seule phrase.  ")

let bullets_and_sentences_tests =
  [
    ( "bullets: the recorded Urtica box, stars dropped, in order",
      `Quick,
      bullets_urtica );
    ( "bullets: a non-bullet and a blank bullet line are dropped",
      `Quick,
      bullets_blank_dropped );
    ( "first_sentences: n=2, n=0, \"L. \" kept, fewer sentences than n",
      `Quick,
      first_sentences_cases );
  ]

(* ---------- code_points ---------- *)

let code_points_tests =
  [
    ( "code_points: ASCII, accented letters counted once, empty",
      `Quick,
      fun () ->
        Alcotest.(check int) "abc" 3 (Wiki_text.code_points "abc");
        Alcotest.(check int) "Pensée" 6 (Wiki_text.code_points "Pensée");
        Alcotest.(check int) "empty" 0 (Wiki_text.code_points "") );
  ]

let suite =
  ( "wiki_text",
    sections_tests
    @ strip_tests
    @ templates_tests
    @ bullets_and_sentences_tests
    @ code_points_tests )
