module Record_plan = Herbier_ui_model.Record_plan

let utc = Fixtures.utc
let plant_id = Fixtures.plant_id

let record_plan =
  let t0 = utc 2026 6 1 0 0 in
  let plant name aliases : Herbier_domain.Plant.t =
    {
      id = plant_id ();
      display_name = name;
      aliases;
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
  let digitale = plant "Digitale pourpre" ["gant de Notre-Dame"]
  and arnica = plant "Arnica" [] in
  let plants = [digitale; arnica] in
  let target =
    Alcotest.testable
      (fun f -> function
        | Record_plan.Existing p ->
            Format.fprintf f "Existing %s" p.display_name
        | Free n -> Format.fprintf f "Free %s" n
        | To_identify -> Format.pp_print_string f "To_identify")
      ( = )
  in
  let pos lat lon : Herbier_domain.Observation.position =
    {lat; lon; accuracy_m = None}
  in
  let obs plant position : Herbier_domain.Observation.t =
    {
      id = Herbier_domain.Ids.Observation_id.fresh ();
      plant_id = plant;
      at = t0;
      position;
      place_label = None;
      place_derived = None;
      note = None;
      created_at = t0;
      updated_at = t0;
      deleted_at = None;
    }
  in
  [
    Alcotest.test_case "target" `Quick (fun () ->
        let t ?chosen s = Record_plan.target ~plants ~chosen s in
        Alcotest.check target "blank" Record_plan.To_identify (t "  ");
        Alcotest.check target "name, case" (Record_plan.Existing digitale)
          (t " digitale POURPRE ");
        Alcotest.check target "alias" (Record_plan.Existing digitale)
          (t "Gant de notre-dame");
        Alcotest.check target "free" (Record_plan.Free "Lis martagon")
          (t " Lis martagon ");
        let arnica' = plant "Arnica" [] in
        Alcotest.check target "chosen wins over a same-name plant"
          (Record_plan.Existing arnica')
          (t ~chosen:arnica' "arnica");
        Alcotest.check target "case folding is ASCII only"
          (Record_plan.Free "érable")
          (Record_plan.target ~plants:[plant "Érable" []] ~chosen:None "érable");
        Alcotest.check target "chosen then edited"
          (Record_plan.Free "Arnica des")
          (t ~chosen:arnica "Arnica des"));
    Alcotest.test_case "seen here: within 500 m, nearest first, once" `Quick
      (fun () ->
        let here = pos 48.0 7.0 in
        let far = plant "Lis martagon" [] and edge = plant "Gentiane" [] in
        (* 0.001° lat ≈ 111 m *)
        let observations =
          [
            obs (Some arnica.id) (Some (pos 48.004 7.0));
            obs (Some digitale.id) (Some (pos 48.001 7.0));
            obs (Some arnica.id) (Some (pos 48.002 7.0));
            obs (Some digitale.id) (Some (pos 48.1 7.0));
            (* ≈ 511 m: outside *)
            obs (Some far.id) (Some (pos 48.0046 7.0));
            (* ≈ 489 m: inside *)
            obs (Some edge.id) (Some (pos 48.0044 7.0));
            obs None (Some (pos 48.0 7.0));
            obs (Some (plant_id ())) (Some (pos 48.0 7.0));
          ]
        in
        Alcotest.(check (list string))
          "names"
          ["Digitale pourpre"; "Arnica"; "Gentiane"]
          (List.map
             (fun (p : Herbier_domain.Plant.t) -> p.display_name)
             (Record_plan.seen_here ~here observations (plants @ [far; edge]))));
    Alcotest.test_case "when and where" `Quick (fun () ->
        let now = utc 2026 11 6 10 0 and fix = Some (pos 1. 2.) in
        let taken = utc 2026 7 1 9 0 and just_now = utc 2026 11 6 9 55 in
        let ww l = Record_plan.when_where ~now ~fix l in
        let position =
          Alcotest.testable
            (fun f (p : Herbier_domain.Observation.position) ->
              Format.fprintf f "%g, %g" p.lat p.lon)
            ( = )
        in
        let when_where =
          Alcotest.(pair (testable Ptime.pp Ptime.equal) (option position))
        in
        Alcotest.check when_where "none" (now, fix) (ww []);
        Alcotest.check when_where "no exif" (now, fix) (ww [(None, None)]);
        Alcotest.check when_where "old exif date, no position: none"
          (taken, None)
          (ww [(Some taken, None)]);
        Alcotest.check when_where "recent exif date, no position: the fix"
          (just_now, fix)
          (ww [(Some just_now, None)]);
        Alcotest.check when_where "exif position only"
          (now, Some (pos 3. 4.))
          (ww [(None, Some (pos 3. 4.))]);
        Alcotest.check when_where "exif both"
          (taken, Some (pos 3. 4.))
          (ww [(Some taken, Some (pos 3. 4.)); (None, None)]);
        Alcotest.check when_where "first photo only" (now, fix)
          (ww [(None, None); (Some taken, Some (pos 3. 4.))]));
  ]
