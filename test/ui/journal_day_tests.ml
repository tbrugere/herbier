module Journal_day = Herbier_ui_model.Journal_day

let utc = Fixtures.utc

let obs ?(hour = 12) ?label ?derived ?pos () : Herbier_domain.Observation.t =
  let t = utc 2026 6 12 hour 0 in
  {
    id = Herbier_domain.Ids.Observation_id.fresh ();
    plant_id = None;
    at = t;
    position =
      Option.map
        (fun (lat, lon) ->
          {Herbier_domain.Observation.lat; lon; accuracy_m = None})
        pos;
    place_label = label;
    place_derived = derived;
    note = None;
    created_at = t;
    updated_at = t;
    deleted_at = None;
  }

let journal_day =
  let place = Alcotest.(option string) in
  [
    Alcotest.test_case "group consecutive" `Quick (fun () ->
        let days =
          Journal_day.group ~date:fst
            [((1, 1, 2), "a"); ((1, 1, 2), "b"); ((1, 1, 1), "c")]
        in
        Alcotest.(check (list (list string)))
          "items"
          [["a"; "b"]; ["c"]]
          (List.map (fun (d : _ Journal_day.t) -> List.map snd d.items) days));
    Alcotest.test_case "a date that comes back is a new day" `Quick (fun () ->
        let days =
          Journal_day.group ~date:fst
            [((1, 1, 2), "a"); ((1, 1, 1), "b"); ((1, 1, 2), "c")]
        in
        Alcotest.(check (list (list string)))
          "items" [["a"]; ["b"]; ["c"]]
          (List.map (fun (d : _ Journal_day.t) -> List.map snd d.items) days));
    Alcotest.test_case "one item, empty" `Quick (fun () ->
        Alcotest.(check int)
          "one day" 1
          (List.length (Journal_day.group ~date:Fun.id [(1, 1, 1)]));
        Alcotest.(check int)
          "no day" 0
          (List.length (Journal_day.group ~date:Fun.id [])));
    Alcotest.test_case "majority label" `Quick (fun () ->
        Alcotest.check place "label" (Some "Col")
          (Journal_day.place
             [
               obs ~label:"Lac" ();
               obs ~label:"Col" ();
               obs ~label:"Col" ();
               obs ~derived:"Près" ();
             ]));
    Alcotest.test_case "tie to the earliest, blank and padded labels" `Quick
      (fun () ->
        (* The store gives a day newest first. *)
        Alcotest.check place "earliest" (Some "Col")
          (Journal_day.place
             [obs ~hour:15 ~label:"Lac" (); obs ~hour:9 ~label:"Col" ()]);
        Alcotest.check place "trimmed, blank ignored" (Some "Lac")
          (Journal_day.place
             [obs ~label:"  " (); obs ~label:" Lac " (); obs ~derived:"Près" ()]));
    Alcotest.test_case "derived, then coordinates" `Quick (fun () ->
        Alcotest.check place "derived" (Some "Près de Colmar")
          (Journal_day.place
             [obs ~pos:(48.1, 7.2) (); obs ~derived:"Près de Colmar" ()]);
        Alcotest.check place "no name, positioned: Lieu inconnu"
          (Some "Lieu inconnu")
          (Journal_day.place [obs (); obs ~pos:(48.0633, 7.0081) ()]);
        Alcotest.check place
          "no name, two different positions: still Lieu inconnu"
          (Some "Lieu inconnu")
          (Journal_day.place
             [obs ~hour:15 ~pos:(48.1, 7.0) (); obs ~hour:9 ~pos:(48.3, 7.2) ()]);
        Alcotest.check place "a nan position is not placeable" None
          (Journal_day.place [obs ~pos:(Float.nan, 7.0) ()]);
        Alcotest.check place "none" None (Journal_day.place [obs ()]));
  ]
