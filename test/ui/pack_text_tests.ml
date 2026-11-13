(* ---------- Pack_text (4m « IGN hors-ligne ») ---------- *)

module Fr_text = Herbier_ui_model.Fr_text
module Pack_text = Herbier_ui_model.Pack_text

let pack_text_size =
  Alcotest.test_case "size: SI units, decimal comma, negative clamps to 0 o"
    `Quick (fun () ->
      List.iter
        (fun (n, expected) ->
          Alcotest.(check string)
            (Printf.sprintf "size %d" n)
            expected (Pack_text.size n))
        [
          (0, "0 o");
          (999, "999 o");
          (1_000, "1 ko");
          (109_832, "110 ko");
          (999_499, "999 ko");
          (999_500, "1,0 Mo");
          (999_999, "1,0 Mo");
          (1_000_000, "1,0 Mo");
          (1_184_172, "1,2 Mo");
          (12_000_000, "12,0 Mo");
          (-1, "0 o");
        ])

let pack_text_title =
  Alcotest.test_case "title: \"<code> · <name>\"" `Quick (fun () ->
      Alcotest.(check string)
        "title" "90 · Territoire de Belfort"
        (Pack_text.title ~code:"90" ~name:"Territoire de Belfort"))

let pack_text_detail =
  Alcotest.test_case "detail: size, then Fr_text.plural of the commune count"
    `Quick (fun () ->
      Alcotest.(check string)
        "plural" "89 ko · 101 communes"
        (Pack_text.detail ~size_bytes:89_000 ~communes:101);
      Alcotest.(check string)
        "singular" "1 ko · 1 commune"
        (Pack_text.detail ~size_bytes:1_000 ~communes:1))

let pack_text_fixed_strings =
  Alcotest.test_case "unreadable, no_pack and attribution are fixed strings"
    `Quick (fun () ->
      Alcotest.(check string)
        "unreadable" "Fichier illisible : supprimez puis retéléchargez."
        Pack_text.unreadable;
      Alcotest.(check string)
        "no_pack"
        "Aucun département téléchargé : « IGN hors-ligne » ne nomme rien."
        Pack_text.no_pack;
      Alcotest.(check string)
        "attribution"
        "Limites communales : IGN, Admin Express COG carto (Licence Ouverte \
         2.0)"
        Pack_text.attribution)

let pack_text =
  [pack_text_size; pack_text_title; pack_text_detail; pack_text_fixed_strings]
