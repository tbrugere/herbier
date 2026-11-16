module Fr_text = Herbier_ui_model.Fr_text

let plural =
  Alcotest.test_case "plural" `Quick (fun () ->
      Alcotest.(check (list string))
        "0 1 2"
        ["0 plante"; "1 plante"; "2 plantes"]
        (List.map (fun n -> Fr_text.plural n "plante" "plantes") [0; 1; 2]))

let size =
  Alcotest.test_case "size: SI units, decimal comma, negative clamps to 0 o"
    `Quick (fun () ->
      List.iter
        (fun (n, expected) ->
          Alcotest.(check string)
            (Printf.sprintf "size %.1f" n)
            expected (Fr_text.size n))
        [
          (0., "0 o");
          (999., "999 o");
          (1_000., "1 ko");
          (109_832., "110 ko");
          (999_499., "999 ko");
          (999_500., "1,0 Mo");
          (999_999., "1,0 Mo");
          (1_000_000., "1,0 Mo");
          (1_184_172., "1,2 Mo");
          (12_000_000., "12,0 Mo");
          (-1., "0 o");
          (999.9, "999 o");
          (2_500_000_000., "2500,0 Mo");
          (5_000_000_000., "5000,0 Mo");
        ])

let fr_text = [plural; size]
