(* Herbier_ui_model.Long_text: the pure threshold deciding whether a 4f text
   gets the expandable-paragraph widget. *)

module Long_text = Herbier_ui_model.Long_text

let repeat n s = String.concat "" (List.init n (fun _ -> s))

let long_text =
  [
    Alcotest.test_case "threshold is 140 code points" `Quick (fun () ->
        Alcotest.(check int) "threshold" 140 Long_text.threshold);
    Alcotest.test_case "exactly 140 code points: not collapsible" `Quick
      (fun () ->
        Alcotest.(check bool)
          "140" false
          (Long_text.collapsible (repeat 140 "a")));
    Alcotest.test_case "141 code points: collapsible" `Quick (fun () ->
        Alcotest.(check bool)
          "141" true
          (Long_text.collapsible (repeat 141 "a")));
    Alcotest.test_case "accented letters are counted once each" `Quick
      (fun () ->
        (* "é" is one code point, not two UTF-8 bytes: 140 of them stay
           under the threshold. *)
        Alcotest.(check bool)
          "140 é" false
          (Long_text.collapsible (repeat 140 "é"));
        Alcotest.(check bool)
          "141 é" true
          (Long_text.collapsible (repeat 141 "é")));
    Alcotest.test_case "a newline makes a short text collapsible" `Quick
      (fun () ->
        Alcotest.(check bool)
          "short with \\n" true
          (Long_text.collapsible "Court.\nDeuxième ligne."));
    Alcotest.test_case "a short text without a newline is not collapsible"
      `Quick (fun () ->
        Alcotest.(check bool)
          "short" false
          (Long_text.collapsible "Un texte court."));
    Alcotest.test_case "surrounding blanks are trimmed before counting" `Quick
      (fun () ->
        Alcotest.(check bool)
          "140 + surrounding blanks" false
          (Long_text.collapsible ("  " ^ repeat 140 "a" ^ "\n\n")));
  ]
