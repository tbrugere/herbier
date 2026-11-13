module Fr_text = Herbier_ui_model.Fr_text

let fr_text =
  [
    Alcotest.test_case "plural" `Quick (fun () ->
        Alcotest.(check (list string))
          "0 1 2"
          ["0 plante"; "1 plante"; "2 plantes"]
          (List.map (fun n -> Fr_text.plural n "plante" "plantes") [0; 1; 2]));
  ]
