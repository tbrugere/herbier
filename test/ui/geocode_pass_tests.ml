(* Herbier_ui_model.Geocode_pass: the geocoding pass's work list, when it
   yields to a new run, and what follows each committed name or rename. *)

module Geocode_pass = Herbier_ui_model.Geocode_pass

let obs = Fixtures.map_obs

(* An item as (observation id, kind) for comparison. *)
let show_kind = function
  | Geocode_pass.Name -> "Name"
  | Geocode_pass.Rename {was} -> "Rename [" ^ was ^ "]"

let summary (items : Geocode_pass.item list) =
  List.map
    (fun (i : Geocode_pass.item) ->
      (Herbier_domain.Ids.Observation_id.to_string i.o.id, show_kind i.kind))
    items

let ids_kinds = Alcotest.(list (pair string string))

let id (o : Herbier_domain.Observation.t) =
  Herbier_domain.Ids.Observation_id.to_string o.id

let after =
  Alcotest.testable
    (fun ppf (a : Geocode_pass.after_save) ->
      Fmt.pf ppf "{outcome = %S; mark_tried = %b; forget = %b}" a.outcome
        a.mark_tried a.forget)
    ( = )

let geocode_pass =
  [
    Alcotest.test_case
      "items: unnamed first, then renames; no position left out" `Quick
      (fun () ->
        let a = obs ~pos:(44.6, 2.0) () and b = obs () in
        let c = obs ~pos:(44.6, 2.0) ~derived:"Près du Champ" () in
        let d = obs ~pos:(44.6, 2.0) () in
        Alcotest.check ids_kinds "order and kinds"
          [(id a, "Name"); (id c, "Rename [Près du Champ]")]
          (summary (Geocode_pass.items ~to_geocode:[a; b] ~to_rename:[c; d])));
    Alcotest.test_case "a rename keeps the name as stored, untrimmed" `Quick
      (fun () ->
        let c = obs ~pos:(44.6, 2.0) ~derived:" Près du Champ " () in
        Alcotest.check ids_kinds "was"
          [(id c, "Rename [ Près du Champ ]")]
          (summary (Geocode_pass.items ~to_geocode:[] ~to_rename:[c])));
    Alcotest.test_case "only a rename yields, and only when asked again" `Quick
      (fun () ->
        let o = obs ~pos:(44.6, 2.0) ~derived:"Près du Champ" () in
        match Geocode_pass.items ~to_geocode:[o] ~to_rename:[o] with
        | [name; rename] ->
            Alcotest.(check bool)
              "name, again" false
              (Geocode_pass.yields name ~again:true);
            Alcotest.(check bool)
              "rename, again" true
              (Geocode_pass.yields rename ~again:true);
            Alcotest.(check bool)
              "rename, not again" false
              (Geocode_pass.yields rename ~again:false)
        | _ -> Alcotest.fail "two items");
    Alcotest.test_case "after a save: log, tried and marker per outcome" `Quick
      (fun () ->
        let rename = Geocode_pass.Rename {was = "Près du Champ"} in
        Alcotest.check after "name, 0 changes"
          {outcome = "unchanged"; mark_tried = true; forget = false}
          (Geocode_pass.after_save Name ~changes:0);
        Alcotest.check after "name, 1 change"
          {outcome = "named"; mark_tried = false; forget = false}
          (Geocode_pass.after_save Name ~changes:1);
        Alcotest.check after "rename, 0 changes: forgotten"
          {outcome = "unchanged"; mark_tried = false; forget = true}
          (Geocode_pass.after_save rename ~changes:0);
        Alcotest.check after "rename, 1 change"
          {outcome = "renamed"; mark_tried = false; forget = true}
          (Geocode_pass.after_save rename ~changes:1));
  ]
