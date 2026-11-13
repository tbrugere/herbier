module Cover = Herbier_ui_model.Cover

let utc = Fixtures.utc
let plant_id = Fixtures.plant_id

let cover =
  let t0 = utc 2026 6 1 0 0 in
  let obs plant : Herbier_domain.Observation.t =
    {
      id = Herbier_domain.Ids.Observation_id.fresh ();
      plant_id = plant;
      at = t0;
      position = None;
      place_label = None;
      place_derived = None;
      note = None;
      created_at = t0;
      updated_at = t0;
      deleted_at = None;
    }
  in
  let photo (o : Herbier_domain.Observation.t) : Herbier_domain.Photo.t =
    let id = Herbier_domain.Ids.Photo_id.fresh () in
    {
      id;
      observation_id = o.id;
      taken_at = t0;
      width = 1;
      height = 1;
      sha256 = "";
      preview_path = "";
      preview_bucket_key = None;
      original_target = App_only;
      drive_file_id = None;
      upload_state = Pending;
      created_at = t0;
      updated_at = t0;
      deleted_at = None;
    }
  in
  let a = plant_id () and b = plant_id () in
  let oa = obs (Some a) and ob = obs (Some b) and on = obs None in
  let p1 = photo oa and p2 = photo ob and p3 = photo oa and p4 = photo on in
  let ids l =
    List.map
      (fun (p : Herbier_domain.Photo.t) ->
        Herbier_domain.Ids.Photo_id.to_string p.id)
      l
  in
  let strs = Alcotest.(list string) in
  [
    Alcotest.test_case "by plant keeps order, skips unlinked" `Quick (fun () ->
        let f = Cover.by_plant [oa; ob; on] [p1; p2; p3; p4] in
        Alcotest.check strs "a" (ids [p1; p3]) (ids (f a));
        Alcotest.check strs "b" (ids [p2]) (ids (f b)));
    Alcotest.test_case "by plant skips a photo of an unknown observation" `Quick
      (fun () ->
        (* [ox] is linked to [a] but not passed: its photo belongs to no
           plant. *)
        let ox = obs (Some a) in
        let p5 = photo ox in
        let f = Cover.by_plant [oa; ob; on] [p1; p5; p3] in
        Alcotest.check strs "a" (ids [p1; p3]) (ids (f a)));
    Alcotest.test_case "cover first, else newest" `Quick (fun () ->
        Alcotest.check strs "chosen"
          (ids [p3; p1])
          (ids (Cover.ordered (Some p3.id) [p1; p3]));
        Alcotest.check strs "gone"
          (ids [p1; p3])
          (ids (Cover.ordered (Some p2.id) [p1; p3]));
        Alcotest.check strs "none chosen"
          (ids [p1; p3])
          (ids (Cover.ordered None [p1; p3])));
    Alcotest.test_case "choose" `Quick (fun () ->
        let one l = ids (Option.to_list l) in
        Alcotest.check strs "none chosen: newest" (ids [p1])
          (one (Cover.choose None [p1; p3]));
        Alcotest.check strs "chosen" (ids [p3])
          (one (Cover.choose (Some p3.id) [p1; p3]));
        Alcotest.check strs "gone: newest" (ids [p1])
          (one (Cover.choose (Some p2.id) [p1; p3]));
        Alcotest.check strs "no photo" [] (one (Cover.choose None [])));
  ]
