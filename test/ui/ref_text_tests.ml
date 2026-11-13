(* Ref_text: texts of 4f's reference block. *)

module Ref_text = Herbier_ui_model.Ref_text
module Source = Herbier_domain.Reference.Source
module Organ = Herbier_domain.Reference.Organ
module Projection = Herbier_refs.Projection

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
  ]
