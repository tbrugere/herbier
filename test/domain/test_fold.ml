(* Fold's terms, folding, endings and in-memory match. test/store checks the
   FTS5 side: a query with no term (Search.match_expression = None) matches
   nothing. *)

module Fold = Herbier_domain.Fold

(* Each case as (query, text, expected). *)
let matches_cases =
  [
    ("schlu", "Col de la Schlucht", true);
    ("col schlucht", "Col de la Schlucht", true);
    ("ecrin", "Les Écrins", true);
    ("ÉCRINS", "les ecrins", true);
    ("digitale", "Digitalis purpurea", true);
    ("bois", "Lisière du bois", true);
    ("oi", "Lisière du bois", false);
    ("jardin potager", "Jardin", false);
    ("", "Jardin", false);
    ("  , ", "Jardin", false);
    ("\xf0\x9f\x8c\xbf" (* 🌿 *), "Jardin", false);
    ("jardin", "", false);
  ]

let matches_runs_what_match_expression_asks () =
  List.iter
    (fun (query, text, expected) ->
      Alcotest.(check bool)
        (Printf.sprintf "matches ~query:%S %S" query text)
        expected (Fold.matches ~query text))
    matches_cases

let terms () =
  List.iter
    (fun (text, expected) ->
      Alcotest.(check (list string))
        (Printf.sprintf "terms %S" text)
        expected (Fold.terms text))
    [
      ("Col de la Schlucht", ["Col"; "de"; "la"; "Schlucht"]);
      ("l'\xc3\x89crin \xe2\x80\x93 sud", ["l"; "\xc3\x89crin"; "sud"]);
      ("\xc2\xab\xc2\xa0Digitale\xc2\xa0\xc2\xbb", ["Digitale"]);
      ("a-b:c(d)", ["a"; "b"; "c"; "d"]);
      ("\xf0\x9f\x8c\xbf jardin", ["jardin"]);
      ("", []);
    ]

let fold () =
  List.iter
    (fun (text, expected) ->
      Alcotest.(check string)
        (Printf.sprintf "fold %S" text)
        expected (Fold.fold text))
    [
      ("\xc3\x89CRINS", "ecrins");
      ("L\xc3\xa0 \xc3\xbf \xc5\xb8", "la y y");
      ("\xc5\x92uvre", "\xc5\x92uvre");
      ("Stra\xc3\x9fe", "stra\xc3\x9fe");
    ]

let strip_ending () =
  List.iter
    (fun (term, expected) ->
      Alcotest.(check string)
        (Printf.sprintf "strip_ending %S" term)
        expected (Fold.strip_ending term))
    [
      ("digitale", "digital");
      ("digitalis", "digital");
      ("pourpre", "pourpr");
      ("roses", "rose");
      ("rosa", "rosa");
      ("lis", "lis");
    ]

let tests =
  [
    ("terms: separators, kept bytes, dropped symbols", `Quick, terms);
    ("fold: ASCII and Latin-1 letters to lower base letters", `Quick, fold);
    ("strip_ending: one ending, 4 bytes kept", `Quick, strip_ending);
    ( "runs in memory what match_expression asks of FTS5 MATCH",
      `Quick,
      matches_runs_what_match_expression_asks );
  ]
