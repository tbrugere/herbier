(* Local_time, To_identify *)

module Local_time = Herbier_ui_model.Local_time
module To_identify = Herbier_ui_model.To_identify

let utc = Fixtures.utc
let obs = Fixtures.map_obs

let local_time =
  (* Paris in 2026: +1 h until 29 Mar 01:00 UTC, +2 h until 25 Oct 01:00 UTC,
     then +1 h. *)
  let spring = utc 2026 3 29 1 0 and autumn = utc 2026 10 25 1 0 in
  let offset t =
    match
      (Ptime.is_earlier t ~than:spring, Ptime.is_earlier t ~than:autumn)
    with
    | true, _ -> 3600
    | false, true -> 7200
    | false, false -> 3600
  in
  (* New York in 2026: -5 h until 8 Mar 07:00 UTC, then -4 h. *)
  let new_york t =
    match Ptime.is_earlier t ~than:(utc 2026 3 8 7 0) with
    | true -> -18000
    | false -> -14400
  in
  let t = Alcotest.testable Ptime.pp Ptime.equal in
  let input ?(offset = offset) s = Local_time.of_input ~offset s in
  [
    Alcotest.test_case "to input" `Quick (fun () ->
        Alcotest.(check string)
          "summer" "2026-06-12T14:32"
          (Local_time.to_input ~tz_offset_s:7200 (utc 2026 6 12 12 32));
        let late =
          Option.get (Ptime.of_date_time ((2026, 6, 12), ((23, 30, 45), 0)))
        in
        Alcotest.(check string)
          "seconds dropped, next day" "2026-06-13T01:30"
          (Local_time.to_input ~tz_offset_s:7200 late));
    Alcotest.test_case "of input, each side of the change" `Quick (fun () ->
        Alcotest.(check (option t))
          "summer"
          (Some (utc 2026 6 12 12 32))
          (input "2026-06-12T14:32");
        Alcotest.(check (option t))
          "winter"
          (Some (utc 2026 11 2 8 5))
          (input "2026-11-02T09:05:00");
        Alcotest.(check (option t))
          "the hour before the autumn change"
          (Some (utc 2026 10 24 23 30))
          (input "2026-10-25T01:30"));
    Alcotest.test_case "of input, around a change" `Quick (fun () ->
        Alcotest.(check (option t))
          "repeated hour: the first one"
          (Some (utc 2026 10 25 0 30))
          (input "2026-10-25T02:30");
        Alcotest.(check (option t))
          "skipped hour, Paris: the offset before"
          (Some (utc 2026 3 29 1 30))
          (input "2026-03-29T02:30");
        Alcotest.(check (option t))
          "skipped hour, New York: the offset before"
          (Some (utc 2026 3 8 7 30))
          (input ~offset:new_york "2026-03-08T02:30");
        Alcotest.(check (option t))
          "New York, after the change"
          (Some (utc 2026 3 8 7 30))
          (input ~offset:new_york "2026-03-08T03:30");
        Alcotest.(check (option t))
          "New York, before the change"
          (Some (utc 2026 3 8 6 30))
          (input ~offset:new_york "2026-03-08T01:30"));
    Alcotest.test_case "of input, rejected" `Quick (fun () ->
        List.iter
          (fun s -> Alcotest.(check (option t)) s None (input s))
          [
            "2026-11-02 09:05";
            "2026-13-02T09:05";
            "2026-+6-12T14:32";
            "2026-06-1_T14:32";
            "0x7e-06-12T14:32";
            "2026-06-12T24:00";
            "2026-06-12T14:60";
            "2026-06-12T14:32:";
          ]);
  ]

let to_identify =
  let o1 = obs () and o2 = obs () and o3 = obs () and o4 = obs () in
  let name o =
    match
      List.find_index
        (fun (x : Herbier_domain.Observation.t) ->
          Herbier_domain.Ids.Observation_id.equal x.id
            o.Herbier_domain.Observation.id)
        [o1; o2; o3; o4]
    with
    | Some i -> i + 1
    | None -> 0
  in
  let pos x l =
    Option.map
      (fun (p : To_identify.position) ->
        (p.index, p.total, Option.map name p.next))
      (To_identify.position x l)
  in
  let p = Alcotest.(option (triple int int (option int))) in
  [
    Alcotest.test_case "position, next wraps" `Quick (fun () ->
        Alcotest.check p "first" (Some (1, 3, Some 2)) (pos o1 [o1; o2; o3]);
        Alcotest.check p "middle" (Some (2, 3, Some 3)) (pos o2 [o1; o2; o3]);
        Alcotest.check p "last wraps"
          (Some (3, 3, Some 1))
          (pos o3 [o1; o2; o3]);
        Alcotest.check p "two, last wraps"
          (Some (2, 2, Some 1))
          (pos o2 [o1; o2]);
        Alcotest.check p "alone" (Some (1, 1, None)) (pos o1 [o1]);
        Alcotest.check p "empty" None (pos o1 []);
        Alcotest.check p "gone" None (pos o4 [o1; o2; o3]));
  ]
