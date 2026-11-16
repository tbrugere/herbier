(* Herbier_identify.Organ: the five organs, their French labels, the sent
   side (Auto / Given), and the "+ <organe>" suggestion. *)

module Organ = Herbier_identify.Organ

let organ = Alcotest.testable Organ.pp Organ.equal

let pp_sent ppf = function
  | Organ.Auto -> Format.pp_print_string ppf "Auto"
  | Organ.Given o -> Format.fprintf ppf "Given %a" Organ.pp o

let sent = Alcotest.testable pp_sent Organ.equal_sent

let pp_suggestion ppf = function
  | Organ.Add o -> Format.fprintf ppf "Add %a" Organ.pp o
  | Organ.Add_photo -> Format.pp_print_string ppf "Add_photo"

let suggestion = Alcotest.testable pp_suggestion Organ.equal_suggestion

(* ---------- to_string / of_string ---------- *)

let round_trip_tests =
  [
    ( "to_string, then of_string, is the identity on every organ",
      `Quick,
      fun () ->
        List.iter
          (fun o ->
            Alcotest.(check (option organ))
              (Organ.to_string o) (Some o)
              (Organ.of_string (Organ.to_string o)))
          Organ.all );
    ( "a name Herbier does not offer gives None",
      `Quick,
      fun () ->
        List.iter
          (fun s ->
            Alcotest.(check (option organ))
              (Printf.sprintf "%S" s) None (Organ.of_string s))
          ["auto"; "other"; "scan"; ""; "Flower"] );
  ]

(* ---------- label ---------- *)

let label_tests =
  [
    ( "Flower's label is \"fleur\"",
      `Quick,
      fun () ->
        Alcotest.(check string) "label" "fleur" (Organ.label Organ.Flower) );
    ( "Leaf's label is \"feuille\"",
      `Quick,
      fun () ->
        Alcotest.(check string) "label" "feuille" (Organ.label Organ.Leaf) );
    ( "Fruit's label is \"fruit\"",
      `Quick,
      fun () ->
        Alcotest.(check string) "label" "fruit" (Organ.label Organ.Fruit) );
    ( "Bark's label is \"écorce\"",
      `Quick,
      fun () ->
        Alcotest.(check string) "label" "écorce" (Organ.label Organ.Bark) );
    ( "Habit's label is \"port\"",
      `Quick,
      fun () -> Alcotest.(check string) "label" "port" (Organ.label Organ.Habit)
    );
  ]

(* ---------- sent_to_string ---------- *)

let sent_to_string_tests =
  [
    ( "Auto is \"auto\"",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "sent_to_string" "auto"
          (Organ.sent_to_string Organ.Auto) );
    ( "Given Leaf is to_string Leaf",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "sent_to_string" "leaf"
          (Organ.sent_to_string (Organ.Given Organ.Leaf)) );
  ]

(* ---------- effective ---------- *)

let effective_tests =
  [
    ( "a given organ wins over what was detected",
      `Quick,
      fun () ->
        Alcotest.(check (option organ))
          "effective" (Some Organ.Leaf)
          (Organ.effective (Organ.Given Organ.Leaf)
             ~detected:(Some Organ.Flower)) );
    ( "auto takes the detected organ",
      `Quick,
      fun () ->
        Alcotest.(check (option organ))
          "effective" (Some Organ.Flower)
          (Organ.effective Organ.Auto ~detected:(Some Organ.Flower)) );
    ( "auto with nothing detected is None",
      `Quick,
      fun () ->
        Alcotest.(check (option organ))
          "effective" None
          (Organ.effective Organ.Auto ~detected:None) );
  ]

(* ---------- suggest ---------- *)

let suggest_cases =
  [
    ("no photo at all", [], Some (Organ.Add Organ.Flower));
    ("one photo, nothing detected", [None], Some (Organ.Add Organ.Flower));
    ("one leaf photo", [Some Organ.Leaf], Some (Organ.Add Organ.Flower));
    ("one flower photo", [Some Organ.Flower], Some (Organ.Add Organ.Leaf));
    ( "a flower and a fruit, still no leaf",
      [Some Organ.Flower; Some Organ.Fruit],
      Some (Organ.Add Organ.Leaf) );
    ( "a leaf and a flower: both covered",
      [Some Organ.Leaf; Some Organ.Flower],
      Some Organ.Add_photo );
    ( "five photos already, none detected: at the cap",
      List.init 5 (fun _ -> None),
      None );
    ("six photos: still at the cap", List.init 6 (fun _ -> None), None);
  ]

let suggest_tests =
  List.map
    (fun (name, photos, expected) ->
      ( name,
        `Quick,
        fun () ->
          Alcotest.(check (option suggestion))
            "suggest" expected (Organ.suggest photos) ))
    suggest_cases

(* ---------- suggestion_label ---------- *)

let suggestion_label_tests =
  [
    ( "Add Flower is \"+ fleur\"",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "suggestion_label" "+ fleur"
          (Organ.suggestion_label (Organ.Add Organ.Flower)) );
    ( "Add Leaf is \"+ feuille\"",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "suggestion_label" "+ feuille"
          (Organ.suggestion_label (Organ.Add Organ.Leaf)) );
    ( "Add_photo is \"+ photo\"",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "suggestion_label" "+ photo"
          (Organ.suggestion_label Organ.Add_photo) );
  ]

(* ---------- sent_of_suggestion ---------- *)

let sent_of_suggestion_tests =
  [
    ( "Add Leaf sends Given Leaf",
      `Quick,
      fun () ->
        Alcotest.(check sent)
          "sent_of_suggestion" (Organ.Given Organ.Leaf)
          (Organ.sent_of_suggestion (Organ.Add Organ.Leaf)) );
    ( "Add_photo sends Auto",
      `Quick,
      fun () ->
        Alcotest.(check sent)
          "sent_of_suggestion" Organ.Auto
          (Organ.sent_of_suggestion Organ.Add_photo) );
  ]

let suites =
  [
    ("organ to_string / of_string", round_trip_tests);
    ("organ label", label_tests);
    ("organ sent_to_string", sent_to_string_tests);
    ("organ effective", effective_tests);
    ("organ suggest", suggest_tests);
    ("organ suggestion_label", suggestion_label_tests);
    ("organ sent_of_suggestion", sent_of_suggestion_tests);
  ]
