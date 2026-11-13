(* Ref_paste: a pasted link -> the plant's id at one source (5a). *)

module Ref_paste = Herbier_ui_model.Ref_paste
module Plant_id = Herbier_domain.Ids.Plant_id
module Gbif = Herbier_refs.Sources.Gbif
module Source = Herbier_domain.Reference.Source
module Link = Herbier_domain.Link
module Plant_ref = Herbier_domain.Reference.Plant_ref

let utc = Fixtures.utc

let ref_paste_str = function
  | Ref_paste.Species k -> Printf.sprintf "Species %d" k
  | Ref_paste.Plant_ref {source; external_id; url} ->
      Printf.sprintf "Plant_ref {%s; %S; %S}" (Source.to_string source)
        external_id url
  | Ref_paste.Not_a_reference -> "Not_a_reference"
  | Ref_paste.Unrecognised -> "Unrecognised"

let paste =
  Alcotest.testable
    (fun f t -> Format.pp_print_string f (ref_paste_str t))
    Ref_paste.equal

let plant_ref ?(plant_id = Plant_id.fresh ()) ~source ~external_id ~url () :
    Plant_ref.t =
  {
    id = Plant_ref.id_of_key ~plant:plant_id ~source;
    plant_id;
    source;
    external_id;
    url;
    created_at = utc 2026 1 1 0 0;
    updated_at = utc 2026 1 1 0 0;
    deleted_at = None;
  }

let ref_paste =
  [
    Alcotest.test_case "a GBIF species link is Species" `Quick (fun () ->
        Alcotest.check paste "species" (Ref_paste.Species 5414995)
          (Ref_paste.of_text "https://www.gbif.org/species/5414995"));
    Alcotest.test_case "a Pl@ntNet species link is a Plant_ref" `Quick
      (fun () ->
        Alcotest.check paste "plantnet"
          (Ref_paste.Plant_ref
             {
               source = Source.Plantnet;
               external_id = "Digitalis purpurea L.";
               url =
                 "https://identify.plantnet.org/k-world-flora/species/Digitalis%20purpurea%20L./data";
             })
          (Ref_paste.of_text
             "https://identify.plantnet.org/fr/k-world-flora/species/Digitalis%20purpurea%20L./data"));
    Alcotest.test_case "a Wikipedia link is a Plant_ref, interwiki external_id"
      `Quick (fun () ->
        Alcotest.check paste "wikipedia"
          (Ref_paste.Plant_ref
             {
               source = Source.Wikipedia;
               external_id = "fr:Digitale pourpre";
               url = "https://fr.wikipedia.org/wiki/Digitale_pourpre";
             })
          (Ref_paste.of_text "https://fr.wikipedia.org/wiki/Digitale_pourpre"));
    Alcotest.test_case "an INPN link is a Plant_ref (Taxref)" `Quick (fun () ->
        Alcotest.check paste "inpn"
          (Ref_paste.Plant_ref
             {
               source = Source.Taxref;
               external_id = "94959";
               url = "https://inpn.mnhn.fr/espece/cd_nom/94959";
             })
          (Ref_paste.of_text "https://inpn.mnhn.fr/espece/cd_nom/94959"));
    Alcotest.test_case "a Tela link drops the -<tab> suffix from the url" `Quick
      (fun () ->
        Alcotest.check paste "tela"
          (Ref_paste.Plant_ref
             {
               source = Source.Tela;
               external_id = "22437";
               url = "https://www.tela-botanica.org/bdtfx-nn-22437";
             })
          (Ref_paste.of_text
             "https://www.tela-botanica.org/bdtfx-nn-22437-synthese"));
    Alcotest.test_case "a POWO link is a Plant_ref, the IPNI lsid kept as is"
      `Quick (fun () ->
        Alcotest.check paste "powo"
          (Ref_paste.Plant_ref
             {
               source = Source.Powo;
               external_id = "urn:lsid:ipni.org:names:802077-1";
               url =
                 "https://powo.science.kew.org/taxon/urn:lsid:ipni.org:names:802077-1";
             })
          (Ref_paste.of_text
             "https://powo.science.kew.org/taxon/urn:lsid:ipni.org:names:802077-1"));
    Alcotest.test_case "an iNat link is a Plant_ref" `Quick (fun () ->
        Alcotest.check paste "inat"
          (Ref_paste.Plant_ref
             {
               source = Source.Inat;
               external_id = "53983";
               url = "https://www.inaturalist.org/taxa/53983";
             })
          (Ref_paste.of_text
             "https://www.inaturalist.org/taxa/53983-Digitalis-purpurea"));
    Alcotest.test_case "a POWO id other than an IPNI lsid is percent-encoded"
      `Quick (fun () ->
        Alcotest.check paste "powo other"
          (Ref_paste.Plant_ref
             {
               source = Source.Powo;
               external_id = "abc:1";
               url = "https://powo.science.kew.org/taxon/abc%3A1";
             })
          (Ref_paste.of_text "https://powo.science.kew.org/taxon/abc:1"));
    Alcotest.test_case
      "an accented or parenthesised Wikipedia title is decoded in the id" `Quick
      (fun () ->
        List.iter
          (fun (text, external_id) ->
            match Ref_paste.of_text text with
            | Ref_paste.Plant_ref {external_id = got; _} ->
                Alcotest.(check string) text external_id got
            | Ref_paste.(Species _ | Not_a_reference | Unrecognised) ->
                Alcotest.failf "%s: expected a Plant_ref" text)
          [
            ( "https://fr.wikipedia.org/wiki/Digitale_%C3%A0_grandes_fleurs",
              "fr:Digitale à grandes fleurs" );
            ("https://fr.wikipedia.org/wiki/Ail_(plante)", "fr:Ail (plante)");
          ]);
    Alcotest.test_case "a Pl@ntUse link is Not_a_reference" `Quick (fun () ->
        Alcotest.check paste "plantuse" Ref_paste.Not_a_reference
          (Ref_paste.of_text
             "https://plantuse.plantnet.org/fr/Digitalis_purpurea"));
    Alcotest.test_case "a Pl@ntNet observation link is Not_a_reference" `Quick
      (fun () ->
        Alcotest.check paste "plantnet observation" Ref_paste.Not_a_reference
          (Ref_paste.of_text
             "https://identify.plantnet.org/fr/observations/1012345678"));
    Alcotest.test_case "plain text is Unrecognised" `Quick (fun () ->
        Alcotest.check paste "text" Ref_paste.Unrecognised
          (Ref_paste.of_text "digitale pourpre"));
    Alcotest.test_case
      "round trip: Link.classify of the stored url matches the text's \
       classification"
      `Quick (fun () ->
        List.iter
          (fun text ->
            match Ref_paste.of_text text with
            | Ref_paste.Plant_ref {url; _} ->
                Alcotest.(check bool)
                  (text ^ ": classify url = classify text")
                  true
                  (Link.equal (Link.classify url) (Link.classify text))
            | _ -> Alcotest.failf "%s: expected a Plant_ref" text)
          [
            "https://identify.plantnet.org/fr/k-world-flora/species/Digitalis%20purpurea%20L./data";
            "https://fr.wikipedia.org/wiki/Digitale_pourpre";
            "https://fr.wikipedia.org/wiki/Digitale_%C3%A0_grandes_fleurs";
            "https://fr.wikipedia.org/wiki/Ail_(plante)";
            "https://powo.science.kew.org/taxon/abc:1";
            "https://inpn.mnhn.fr/espece/cd_nom/94959";
            "https://www.tela-botanica.org/bdtfx-nn-22437-synthese";
            "https://powo.science.kew.org/taxon/urn:lsid:ipni.org:names:802077-1";
            "https://www.inaturalist.org/taxa/53983-Digitalis-purpurea";
          ]);
    Alcotest.test_case
      "a url with a query string and fragment gives the same Plant_ref as the \
       bare url"
      `Quick (fun () ->
        Alcotest.check paste "with query and fragment"
          (Ref_paste.of_text "https://inpn.mnhn.fr/espece/cd_nom/94959")
          (Ref_paste.of_text
             "https://inpn.mnhn.fr/espece/cd_nom/94959?tab=taxo#onglet"));
    Alcotest.test_case "text around the url is still classified" `Quick
      (fun () ->
        Alcotest.check paste "surrounded by text"
          (Ref_paste.of_text "https://inpn.mnhn.fr/espece/cd_nom/94959")
          (Ref_paste.of_text "voir https://inpn.mnhn.fr/espece/cd_nom/94959"));
    Alcotest.test_case "removable: every source but Gbif" `Quick (fun () ->
        Alcotest.(check bool)
          "Gbif: not removable" false
          (Ref_paste.removable
             (plant_ref ~source:Source.Gbif ~external_id:"5414995"
                ~url:(Gbif.species_url 5414995) ()));
        List.iter
          (fun source ->
            Alcotest.(check bool)
              (Source.to_string source ^ ": removable")
              true
              (Ref_paste.removable
                 (plant_ref ~source ~external_id:"x"
                    ~url:"https://example.invalid/x" ())))
          (List.filter
             (fun s -> not (Source.to_string s = Source.to_string Source.Gbif))
             Source.all));
    Alcotest.test_case "label: source name, a middle dot, external_id" `Quick
      (fun () ->
        Alcotest.(check string)
          "label" "GBIF · 5414995"
          (Ref_paste.label
             (plant_ref ~source:Source.Gbif ~external_id:"5414995"
                ~url:(Gbif.species_url 5414995) ()));
        Alcotest.(check string)
          "Wikipédia label" "Wikipédia · fr:Digitale pourpre"
          (Ref_paste.label
             (plant_ref ~source:Source.Wikipedia
                ~external_id:"fr:Digitale pourpre"
                ~url:"https://fr.wikipedia.org/wiki/Digitale_pourpre" ())));
  ]

(* equal on every pair of a set covering each constructor and each field of
   Plant_ref: true exactly on the same value. *)
let ref_paste_equal_pairs () =
  let values =
    [
      Ref_paste.Species 1;
      Species 2;
      Plant_ref {source = Source.Powo; external_id = "a"; url = "u"};
      Plant_ref {source = Source.Tela; external_id = "a"; url = "u"};
      Plant_ref {source = Source.Powo; external_id = "b"; url = "u"};
      Plant_ref {source = Source.Powo; external_id = "a"; url = "v"};
      Not_a_reference;
      Unrecognised;
    ]
  in
  List.iteri
    (fun i a ->
      List.iteri
        (fun j b ->
          Alcotest.(check bool)
            (Printf.sprintf "values %d and %d" i j)
            (Int.equal i j) (Ref_paste.equal a b))
        values)
    values

let ref_paste =
  ref_paste
  @ [
      Alcotest.test_case "equal: true exactly on the same value" `Quick
        ref_paste_equal_pairs;
    ]
