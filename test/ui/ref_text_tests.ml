(* Ref_text: texts of 4f's reference block. *)

module Ref_text = Herbier_ui_model.Ref_text
module Source = Herbier_domain.Reference.Source
module Organ = Herbier_domain.Reference.Organ
module Projection = Herbier_refs.Projection

let area code name : Projection.area = {code; name}

let ref_text =
  [
    Alcotest.test_case "source_name for every source" `Quick (fun () ->
        let case expected source =
          Alcotest.(check string)
            (Source.to_string source) expected
            (Ref_text.source_name source)
        in
        case "GBIF" Source.Gbif;
        case "Wikidata" Source.Wikidata;
        case "Wikipédia" Source.Wikipedia;
        case "POWO" Source.Powo;
        case "IPNI" Source.Ipni;
        case "INPN" Source.Taxref;
        case "Tela Botanica" Source.Tela;
        case "EPPO" Source.Eppo;
        case "iNaturalist" Source.Inat;
        case "Pl@ntNet" Source.Plantnet);
    Alcotest.test_case
      "names_source_line: family and sources, no family, neither, family alone"
      `Quick (fun () ->
        Alcotest.(check string)
          "family and sources" "Plantaginaceae · GBIF, Wikidata"
          (Ref_text.names_source_line ~family:(Some "Plantaginaceae")
             [Source.Gbif; Source.Wikidata]);
        Alcotest.(check string)
          "no family" "GBIF, Wikidata"
          (Ref_text.names_source_line ~family:None
             [Source.Gbif; Source.Wikidata]);
        Alcotest.(check string)
          "neither" ""
          (Ref_text.names_source_line ~family:None []);
        Alcotest.(check string)
          "family alone, no separator" "Plantaginaceae"
          (Ref_text.names_source_line ~family:(Some "Plantaginaceae") []));
    Alcotest.test_case "names_line joins with \", \"" `Quick (fun () ->
        Alcotest.(check string)
          "names_line" "Digitale pourpre, grande digitale"
          (Ref_text.names_line
             {
               Projection.lang = Projection.Lang.Fr;
               names = ["Digitale pourpre"; "grande digitale"];
             }));
    Alcotest.test_case "sources_line: joined, empty for []" `Quick (fun () ->
        Alcotest.(check string)
          "two sources" "GBIF, Wikidata"
          (Ref_text.sources_line [Source.Gbif; Source.Wikidata]);
        Alcotest.(check string)
          "one source" "GBIF"
          (Ref_text.sources_line [Source.Gbif]);
        Alcotest.(check string) "empty" "" (Ref_text.sources_line []));
    Alcotest.test_case "origin_line: 0, 1, 6, 7 and 80 names (\"et n autres\")"
      `Quick (fun () ->
        let names n = List.init n (fun i -> Printf.sprintf "C%02d" (i + 1)) in
        Alcotest.(check (option string))
          "0 names" None (Ref_text.origin_line []);
        Alcotest.(check (option string))
          "1 name" (Some "C01")
          (Ref_text.origin_line (names 1));
        Alcotest.(check (option string))
          "6 names, all joined" (Some "C01, C02, C03, C04, C05, C06")
          (Ref_text.origin_line (names 6));
        Alcotest.(check (option string))
          "7 names: first 5 then et 2 autres"
          (Some "C01, C02, C03, C04, C05 et 2 autres")
          (Ref_text.origin_line (names 7));
        Alcotest.(check (option string))
          "80 names: first 5 then et 75 autres"
          (Some "C01, C02, C03, C04, C05 et 75 autres")
          (Ref_text.origin_line (names 80)));
    Alcotest.test_case
      "red_list: every listed IUCN category, no-data categories, an unknown \
       string passed through"
      `Quick (fun () ->
        let case expected cat =
          Alcotest.(check (option string))
            (Printf.sprintf "red_list %S" cat)
            expected (Ref_text.red_list cat)
        in
        case (Some "LC · préoccupation mineure") "LEAST_CONCERN";
        case (Some "NT · quasi menacée") "NEAR_THREATENED";
        case (Some "VU · vulnérable") "VULNERABLE";
        case (Some "EN · en danger") "ENDANGERED";
        case (Some "CR · en danger critique") "CRITICALLY_ENDANGERED";
        case (Some "EW · éteinte à l'état sauvage") "EXTINCT_IN_THE_WILD";
        case (Some "EX · éteinte") "EXTINCT";
        case (Some "DD · données insuffisantes") "DATA_DEFICIENT";
        case None "NOT_EVALUATED";
        case None "NOT_APPLICABLE";
        case (Some "FOO") "FOO");
    Alcotest.test_case "month_letter: 1, 12, and out of range" `Quick (fun () ->
        Alcotest.(check string) "january" "J" (Ref_text.month_letter 1);
        Alcotest.(check string) "december" "D" (Ref_text.month_letter 12);
        Alcotest.(check string) "zero" "" (Ref_text.month_letter 0);
        Alcotest.(check string) "thirteen" "" (Ref_text.month_letter 13));
    Alcotest.test_case
      "months_text: runs, wrap across the year, dedup, invalid values dropped, \
       all twelve, empty"
      `Quick (fun () ->
        let case what expected months =
          Alcotest.(check string) what expected (Ref_text.months_text months)
        in
        case "a single run" "juin – août" [6; 7; 8];
        case "wraps December to January" "décembre – février" [12; 1; 2];
        case "two runs" "mars – avril, septembre" [3; 4; 9];
        case "one month" "mai" [5];
        case "all twelve" "toute l'année" (List.init 12 (fun i -> i + 1));
        case "empty" "" [];
        case "duplicates and an out-of-range value dropped" "juin – août"
          [8; 6; 7; 7];
        case "an invalid value dropped, one month left" "juin" [13; 6];
        case "a wrapping run after a plain month, ordered by first month"
          "mai, novembre – janvier" [11; 12; 1; 5];
        case "the smallest wrap" "décembre – janvier" [1; 12];
        case "eleven months are a wrapping run, not the whole year"
          "juillet – mai"
          [1; 2; 3; 4; 5; 7; 8; 9; 10; 11; 12]);
    Alcotest.test_case "organ_label for every organ" `Quick (fun () ->
        let case expected organ =
          Alcotest.(check string)
            (Organ.to_string organ) expected
            (Ref_text.organ_label organ)
        in
        case "fleur" Organ.Flower;
        case "feuille" Organ.Leaf;
        case "fruit" Organ.Fruit;
        case "port" Organ.Habit);
    Alcotest.test_case "credits: dedup by (attribution, licence), order, empty"
      `Quick (fun () ->
        let image ~attribution ~licence : Herbier_domain.Reference.Image.t =
          {
            plant_id = Herbier_domain.Ids.Plant_id.fresh ();
            source = Source.Plantnet;
            organ = Organ.Flower;
            remote_url = "https://bs.plantnet.org/image/o/x";
            licence;
            attribution;
            thumb_path = None;
          }
        in
        Alcotest.(check string) "empty" "" (Ref_text.credits []);
        Alcotest.(check string)
          "order kept, a duplicate (attribution, licence) dropped"
          "Photos : A (cc-by-sa), B (cc-by)"
          (Ref_text.credits
             [
               image ~attribution:"A" ~licence:"cc-by-sa";
               image ~attribution:"B" ~licence:"cc-by";
               image ~attribution:"A" ~licence:"cc-by-sa";
             ]);
        Alcotest.(check string)
          "same attribution, another licence: both kept"
          "Photos : A (cc-by-sa), A (cc-by)"
          (Ref_text.credits
             [
               image ~attribution:"A" ~licence:"cc-by-sa";
               image ~attribution:"A" ~licence:"cc-by";
             ]));
    Alcotest.test_case "link_label is source_name with an arrow" `Quick
      (fun () ->
        Alcotest.(check string)
          "GBIF" "GBIF ↗"
          (Ref_text.link_label Source.Gbif);
        Alcotest.(check string)
          "Pl@ntNet" "Pl@ntNet ↗"
          (Ref_text.link_label Source.Plantnet));
    Alcotest.test_case "area_name: a known code, an unknown one, no code" `Quick
      (fun () ->
        Alcotest.(check string)
          "a known WGSRPD code is translated" "Belgique"
          (Ref_text.area_name (area (Some "BGM") "Belgium"));
        Alcotest.(check string)
          "an unknown code falls back to the GBIF (English) name" "Atlantis"
          (Ref_text.area_name (area (Some "ZZZ") "Atlantis"));
        Alcotest.(check string)
          "no code: the name as given" "France"
          (Ref_text.area_name (area None "France")));
    Alcotest.test_case "other_languages is the disclosure's fixed label" `Quick
      (fun () ->
        Alcotest.(check string)
          "other_languages" "Autres langues" Ref_text.other_languages);
    Alcotest.test_case
      "origin_names: translated, a coded and an uncoded duplicate merged, \
       French order"
      `Quick (fun () ->
        Alcotest.(check (list string))
          "FRA and the uncoded « france » are one; « Îles Canaries » sorts \
           under i"
          ["Allemagne"; "Belgique"; "France"; "Îles Canaries"]
          (Ref_text.origin_names
             [
               area (Some "GER") "Germany";
               area (Some "BGM") "Belgium";
               area (Some "FRA") "France";
               area None "france";
               area (Some "CNY") "Canary Is.";
             ]));
    Alcotest.test_case
      "origin_names: folded duplicates dropped, first spelling kept" `Quick
      (fun () ->
        Alcotest.(check (list string))
          "accented names folded, a duplicate of \"Ane\" dropped"
          ["Ane"; "éa"; "Zèbre"]
          (Ref_text.origin_names
             (List.map (area None) ["Zèbre"; "Ane"; "Âne"; "éa"]));
        Alcotest.(check (list string))
          "[] areas give []" [] (Ref_text.origin_names []));
    Alcotest.test_case
      "fr_status: every listed INPN status, an unknown string gives no chip"
      `Quick (fun () ->
        let case expected s =
          Alcotest.(check (option string))
            (Printf.sprintf "fr_status %S" s)
            expected (Ref_text.fr_status s)
        in
        case (Some "Indigène") "PRESENT";
        case (Some "Endémique") "ENDEMIC";
        case (Some "Subendémique") "SUBENDEMIC";
        case (Some "Cryptogène") "CRYPTOGENIC";
        case (Some "Introduite") "INTRODUCED";
        case (Some "Introduite envahissante") "INVASIVE";
        case (Some "Introduite non établie") "NOT_NATURALIZED";
        case (Some "Occasionnelle") "OCCASIONAL";
        case (Some "Présence douteuse") "DOUBTFUL";
        case (Some "Absente") "ABSENT";
        case (Some "Disparue") "DISAPPEARED";
        case (Some "Éteinte") "EXTINCT";
        case None "FOO";
        case None "");
    Alcotest.test_case
      "fr_protection: Not_protected, National, Local with one place, Local \
       with several"
      `Quick (fun () ->
        Alcotest.(check string)
          "Not_protected" "Non protégée"
          (Ref_text.fr_protection Projection.Not_protected);
        Alcotest.(check string)
          "National" "Protégée en France"
          (Ref_text.fr_protection Projection.National);
        Alcotest.(check string)
          "Local [one]" "Protégée (Alsace)"
          (Ref_text.fr_protection (Projection.Local ["Alsace"]));
        Alcotest.(check string)
          "Local [several]" "Protégée localement"
          (Ref_text.fr_protection (Projection.Local ["Alsace"; "Le Cher"]));
        Alcotest.(check string)
          "Local []" "Protégée localement"
          (Ref_text.fr_protection (Projection.Local [])));
    Alcotest.test_case "fr_places: 0, 1, 2 and 7 names" `Quick (fun () ->
        let names n =
          List.init n (fun i ->
              Printf.sprintf "%c" (Char.chr (Char.code 'a' + i)))
        in
        Alcotest.(check (option string))
          "Not_protected" None
          (Ref_text.fr_places Projection.Not_protected);
        Alcotest.(check (option string))
          "National" None
          (Ref_text.fr_places Projection.National);
        Alcotest.(check (option string))
          "Local [0 names]" None
          (Ref_text.fr_places (Projection.Local []));
        Alcotest.(check (option string))
          "Local [1 name]" None
          (Ref_text.fr_places (Projection.Local (names 1)));
        Alcotest.(check (option string))
          "Local [2 names]" (Some "Protection : a, b")
          (Ref_text.fr_places (Projection.Local (names 2)));
        Alcotest.(check (option string))
          "Local [7 names]" (Some "Protection : a, b, c, d, e et 2 autres")
          (Ref_text.fr_places (Projection.Local (names 7))));
    Alcotest.test_case
      "fr_red_list: every listed category, NA/NE give no line, an unknown \
       category with and without a description"
      `Quick (fun () ->
        let case expected ~category ~description =
          Alcotest.(check (option string))
            (Printf.sprintf "fr_red_list %S" category)
            expected
            (Ref_text.fr_red_list {Projection.category; description})
        in
        case (Some "Liste rouge : LC · préoccupation mineure") ~category:"LC"
          ~description:None;
        case (Some "Liste rouge : NT · quasi menacée") ~category:"NT"
          ~description:None;
        case (Some "Liste rouge : VU · vulnérable") ~category:"VU"
          ~description:None;
        case (Some "Liste rouge : EN · en danger") ~category:"EN"
          ~description:None;
        case (Some "Liste rouge : CR · en danger critique") ~category:"CR"
          ~description:None;
        case (Some "Liste rouge : DD · données insuffisantes") ~category:"DD"
          ~description:None;
        case (Some "Liste rouge : RE · disparue en France") ~category:"RE"
          ~description:None;
        case (Some "Liste rouge : EW · éteinte à l'état sauvage") ~category:"EW"
          ~description:(Some "Éteinte à l'état sauvage");
        case (Some "Liste rouge : EX · éteinte") ~category:"EX"
          ~description:None;
        case None ~category:"NA" ~description:None;
        case None ~category:"NE" ~description:None;
        case (Some "Liste rouge : XX · truc") ~category:"XX"
          ~description:(Some "Truc");
        case (Some "Liste rouge : XX") ~category:"XX" ~description:None);
  ]
