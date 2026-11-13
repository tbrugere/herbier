module Collection_filter = Herbier_ui_model.Collection_filter
module Plant_id = Herbier_domain.Ids.Plant_id

let p1 = Fixtures.p1
let p2 = Fixtures.p2
let p3 = Fixtures.p3
let obs = Fixtures.plant_obs

let collection_filter =
  let open Collection_filter in
  let t1 = Herbier_domain.Ids.Tag_id.fresh ()
  and t2 = Herbier_domain.Ids.Tag_id.fresh () in
  let link tag_id plant_id : Herbier_domain.Tag.Plant_tag.t =
    {
      id = Herbier_domain.Ids.Plant_tag_id.of_key ~plant:plant_id ~tag:tag_id;
      plant_id;
      tag_id;
      created_at = Ptime.epoch;
      updated_at = Ptime.epoch;
      deleted_at = None;
    }
  in
  let ids =
    Alcotest.testable
      (Fmt.of_to_string Herbier_domain.Ids.Tag_id.to_string)
      Herbier_domain.Ids.Tag_id.equal
  in
  [
    Alcotest.test_case "tagged: the plants of each selected tag" `Quick
      (fun () ->
        let links = [link t1 p1; link t2 p2; link t1 p3] in
        Alcotest.(check (list (list bool)))
          "t2 then t1"
          [[false; true; false]; [true; false; true]]
          (List.map
             (fun ps ->
               List.map
                 (fun p -> List.exists (Plant_id.equal p) ps)
                 [p1; p2; p3])
             (tagged links [t2; t1]));
        Alcotest.(check int) "none selected" 0 (List.length (tagged links [])));
    Alcotest.test_case "toggle_tag" `Quick (fun () ->
        Alcotest.(check (list ids)) "add" [t2; t1] (toggle_tag t2 [t1]);
        Alcotest.(check (list ids)) "remove" [t1] (toggle_tag t2 [t2; t1]));
    Alcotest.test_case "counts" `Quick (fun () ->
        let c =
          counts [obs (Some p1); obs None; obs (Some p1); obs (Some p2)]
        in
        Alcotest.(check (list int))
          "p1 p2 p3" [2; 1; 0]
          (List.map (count c) [p1; p2; p3]));
    Alcotest.test_case "no observation" `Quick (fun () ->
        Alcotest.(check int) "zero" 0 (count (counts []) p1));
    Alcotest.test_case "tags: none selected keeps all" `Quick (fun () ->
        Alcotest.(check bool) "kept" true (has_all_tags ~tagged:[] p3));
    Alcotest.test_case "tags: one" `Quick (fun () ->
        let tagged = [[p1; p2]] in
        Alcotest.(check (list bool))
          "p1 p2 p3" [true; true; false]
          (List.map (has_all_tags ~tagged) [p1; p2; p3]));
    Alcotest.test_case "tags: all required" `Quick (fun () ->
        let tagged = [[p1; p2]; [p2; p3]] in
        Alcotest.(check (list bool))
          "p1 p2 p3" [false; true; false]
          (List.map (has_all_tags ~tagged) [p1; p2; p3]));
  ]
