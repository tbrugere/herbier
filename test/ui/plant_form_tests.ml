module Plant_form = Herbier_ui_model.Plant_form

let utc = Fixtures.utc
let tag_id = Fixtures.tag_id
let plant_id = Fixtures.plant_id

let plant_form =
  let t0 = utc 2026 6 1 0 0 in
  let tag name : Herbier_domain.Tag.t =
    {id = tag_id (); name; created_at = t0; updated_at = t0; deleted_at = None}
  in
  let forest = tag "Forêt"
  and toxic = tag "Toxique"
  and garden = tag "Jardin" in
  let plant : Herbier_domain.Plant.t =
    {
      id = plant_id ();
      display_name = "Digitale";
      aliases = ["gant de Notre-Dame"];
      scientific_name = None;
      authorship = None;
      gbif_key = None;
      notes = "";
      notes_updated_at = None;
      cover_photo_id = None;
      created_at = t0;
      updated_at = t0;
      deleted_at = None;
    }
  in
  let all = [forest; toxic; garden] in
  let f0 = Plant_form.of_plant plant [forest] in
  let names f = List.map Plant_form.tag_name f.Plant_form.tags in
  let strs = Alcotest.(list string) in
  let ids = List.map Herbier_domain.Ids.Tag_id.to_string in
  [
    Alcotest.test_case "unchanged form, no change" `Quick (fun () ->
        let c = Plant_form.diff ~before:plant ~before_tags:[forest] f0 in
        Alcotest.(check bool) "plant" true (Option.is_none c.plant);
        Alcotest.check strs "create_tags" [] c.create_tags;
        Alcotest.check strs "link" [] (ids c.link);
        Alcotest.check strs "unlink" [] (ids c.unlink));
    Alcotest.test_case "a padded but equal name is no change" `Quick (fun () ->
        let c =
          Plant_form.diff ~before:plant ~before_tags:[forest]
            {f0 with name = " Digitale "}
        in
        Alcotest.(check bool) "plant" true (Option.is_none c.plant));
    Alcotest.test_case "tags: existing by name, created, duplicate, blank"
      `Quick (fun () ->
        let f =
          f0
          |> Plant_form.add_tag ~all " toxique "
          |> Plant_form.add_tag ~all "Lisière"
          |> Plant_form.add_tag ~all "forêt"
          |> Plant_form.add_tag ~all "  "
        in
        Alcotest.check strs "tags" ["Forêt"; "Toxique"; "Lisière"] (names f);
        let c =
          Plant_form.diff ~before:plant ~before_tags:[forest]
            (Plant_form.remove_tag (Plant_form.Existing forest) f)
        in
        Alcotest.check strs "created" ["Lisière"] c.create_tags;
        Alcotest.check strs "link toxic" (ids [toxic.id]) (ids c.link);
        Alcotest.check strs "unlink forest" (ids [forest.id]) (ids c.unlink));
    Alcotest.test_case "a created tag: deduplicated, then removed" `Quick
      (fun () ->
        let f =
          f0
          |> Plant_form.add_tag ~all "Lisière"
          |> Plant_form.add_tag ~all "lisière"
        in
        Alcotest.check strs "tags" ["Forêt"; "Lisière"] (names f);
        let c =
          Plant_form.diff ~before:plant ~before_tags:[forest]
            (Plant_form.remove_tag (Plant_form.Created "Lisière") f)
        in
        Alcotest.check strs "created" [] c.create_tags);
    Alcotest.test_case "name and aliases" `Quick (fun () ->
        let f =
          {
            (Plant_form.add_alias "Gant de notre-dame" f0) with
            name = "  Digitale pourpre ";
          }
        in
        let f = Plant_form.add_alias "doigtier" f in
        Alcotest.check strs "aliases"
          ["gant de Notre-Dame"; "doigtier"]
          f.aliases;
        let c = Plant_form.diff ~before:plant ~before_tags:[forest] f in
        Alcotest.(check (option string))
          "name" (Some "Digitale pourpre")
          (Option.map
             (fun (p : Herbier_domain.Plant.t) -> p.display_name)
             c.plant);
        Alcotest.(check bool)
          "blank invalid" false
          (Plant_form.valid {f with name = " "}));
    Alcotest.test_case "cover: chosen, kept, cleared" `Quick (fun () ->
        let pid = Herbier_domain.Ids.Photo_id.fresh () in
        let cover (p : Herbier_domain.Plant.t option) =
          Option.map
            (fun (p : Herbier_domain.Plant.t) ->
              Option.map Herbier_domain.Ids.Photo_id.to_string p.cover_photo_id)
            p
        in
        let c =
          Plant_form.diff ~before:plant ~before_tags:[forest]
            {f0 with cover = Some pid}
        in
        Alcotest.(check (option (option string)))
          "chosen"
          (Some (Some (Herbier_domain.Ids.Photo_id.to_string pid)))
          (cover c.plant);
        Alcotest.(check (option string))
          "name kept" (Some "Digitale")
          (Option.map
             (fun (p : Herbier_domain.Plant.t) -> p.display_name)
             c.plant);
        let with_cover = {plant with cover_photo_id = Some pid} in
        let f = Plant_form.of_plant with_cover [forest] in
        Alcotest.(check (option string))
          "of_plant"
          (Some (Herbier_domain.Ids.Photo_id.to_string pid))
          (Option.map Herbier_domain.Ids.Photo_id.to_string f.cover);
        Alcotest.(check bool)
          "kept: no change" true
          (Option.is_none
             (Plant_form.diff ~before:with_cover ~before_tags:[forest] f).plant);
        Alcotest.(check (option (option string)))
          "cleared" (Some None)
          (cover
             (Plant_form.diff ~before:with_cover ~before_tags:[forest]
                {f with cover = None})
               .plant));
    Alcotest.test_case "aliases only" `Quick (fun () ->
        let c =
          Plant_form.diff ~before:plant ~before_tags:[forest]
            (Plant_form.add_alias "doigtier" f0)
        in
        Alcotest.(check (option strs))
          "aliases"
          (Some ["gant de Notre-Dame"; "doigtier"])
          (Option.map (fun (p : Herbier_domain.Plant.t) -> p.aliases) c.plant));
    Alcotest.test_case "remove_alias" `Quick (fun () ->
        let c =
          Plant_form.diff ~before:plant ~before_tags:[forest]
            (Plant_form.remove_alias "gant de Notre-Dame" f0)
        in
        Alcotest.(check (option strs))
          "aliases" (Some [])
          (Option.map (fun (p : Herbier_domain.Plant.t) -> p.aliases) c.plant));
    Alcotest.test_case "a new plant: from a blank record" `Quick (fun () ->
        let blank = {plant with display_name = ""; aliases = []} in
        let f =
          {(Plant_form.of_plant blank []) with name = "Digitale"}
          |> Plant_form.add_tag ~all "Toxique"
          |> Plant_form.add_tag ~all "Lisière"
        in
        let c = Plant_form.diff ~before:blank ~before_tags:[] f in
        Alcotest.(check (option string))
          "name" (Some "Digitale")
          (Option.map
             (fun (p : Herbier_domain.Plant.t) -> p.display_name)
             c.plant);
        Alcotest.check strs "created" ["Lisière"] c.create_tags;
        Alcotest.check strs "link" (ids [toxic.id]) (ids c.link);
        Alcotest.check strs "unlink" [] (ids c.unlink));
  ]
