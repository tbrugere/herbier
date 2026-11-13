(* Journal_filter: the year of an observation is its UTC year here. *)

module Fr_date = Herbier_ui_model.Fr_date
module Journal_filter = Herbier_ui_model.Journal_filter

let utc = Fixtures.utc
let p1 = Fixtures.p1
let p2 = Fixtures.p2
let p3 = Fixtures.p3
let obs = Fixtures.plant_obs

let journal_filter =
  let year_of (o : Herbier_domain.Observation.t) =
    Fr_date.year ~tz_offset_s:0 o.at
  in
  let at y o = {o with Herbier_domain.Observation.at = utc y 6 1 12 0} in
  let o1 = at 2025 (obs (Some p1))
  and o2 = at 2026 (obs (Some p2))
  and o3 = at 2026 (obs None) in
  let all = [o1; o2; o3] in
  let kept ?year ?(to_identify_only = false) ?(tagged = []) () =
    List.map (Journal_filter.keep ~year_of ~year ~to_identify_only ~tagged) all
  in
  let bools = Alcotest.(list bool) in
  [
    Alcotest.test_case "no filter keeps all" `Quick (fun () ->
        Alcotest.check bools "kept" [true; true; true] (kept ()));
    Alcotest.test_case "year" `Quick (fun () ->
        Alcotest.check bools "2026" [false; true; true] (kept ~year:2026 ()));
    Alcotest.test_case "à identifier" `Quick (fun () ->
        Alcotest.check bools "no plant" [false; false; true]
          (kept ~to_identify_only:true ()));
    Alcotest.test_case "tags: all required, no plant left out" `Quick (fun () ->
        Alcotest.check bools "p1 and p2 tagged" [true; true; false]
          (kept ~tagged:[[p1; p2]] ());
        Alcotest.check bools "only p2 has both" [false; true; false]
          (kept ~tagged:[[p1; p2]; [p2]] ()));
    Alcotest.test_case "filters combine" `Quick (fun () ->
        Alcotest.check bools "2026 and tagged" [false; true; false]
          (kept ~year:2026 ~tagged:[[p1; p2]] ()));
    Alcotest.test_case "year chips: newest first, a selected year stays" `Quick
      (fun () ->
        Alcotest.(check (list int))
          "present" [2026; 2025]
          (Journal_filter.year_chips ~year_of ~year:None all);
        Alcotest.(check (list int))
          "selected, none left" [2026; 2025; 2024]
          (Journal_filter.year_chips ~year_of ~year:(Some 2024) all);
        Alcotest.(check (list int))
          "empty" []
          (Journal_filter.year_chips ~year_of ~year:None []));
    Alcotest.test_case "à identifier chip stays while on" `Quick (fun () ->
        let chip = Alcotest.(option int) in
        Alcotest.check chip "count" (Some 1)
          (Journal_filter.to_identify_chip ~to_identify_only:false all);
        Alcotest.check chip "none: no chip" None
          (Journal_filter.to_identify_chip ~to_identify_only:false [o1; o2]);
        Alcotest.check chip "none, filter on" (Some 0)
          (Journal_filter.to_identify_chip ~to_identify_only:true [o1; o2]));
  ]
