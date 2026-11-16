(* ---------- Pack_text (4m « IGN hors-ligne ») ---------- *)

module Pack_text = Herbier_ui_model.Pack_text

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

let pack_text = [pack_text_title; pack_text_detail; pack_text_fixed_strings]
