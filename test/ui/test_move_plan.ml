(* 5b « Déplacer le point »: the pure logic of app/ui_model/move_plan.ml. No
   fixtures: hand-written observations and points. *)

module Move_plan = Herbier_ui_model.Move_plan
module Observation = Herbier_domain.Observation
module Places = Herbier_domain.Places
module Ids = Herbier_domain.Ids
module Value = Herbier_test_support.Value

(* ---------- building observations and points ---------- *)

let id_string n = Printf.sprintf "00000000-0000-4000-8000-%012d" n

let obs_id n =
  match Ids.Observation_id.of_string (id_string n) with
  | Some id -> id
  | None -> Alcotest.failf "Observation_id.of_string %S gave None" (id_string n)

let plant_id n =
  match Ids.Plant_id.of_string (id_string n) with
  | Some id -> id
  | None -> Alcotest.failf "Plant_id.of_string %S gave None" (id_string n)

let time = Value.time
let t0 = time "2026-06-01T00:00:00Z"
let t1 = time "2026-11-10T09:00:00Z"
let t2 = time "2026-11-10T09:05:00Z"

(* [obs ~id ~at]: a live observation with no plant, position or note by
   default. *)
let obs ?plant ?pos ?place_label ?place_derived ?place_detail ?note
    ?(created_at = t0) ?(updated_at = t0) ?deleted_at ~id ~at () : Observation.t
    =
  {
    id = obs_id id;
    plant_id = Option.map plant_id plant;
    at;
    position = pos;
    place_label;
    place_derived;
    place_detail;
    note;
    created_at;
    updated_at;
    deleted_at;
  }

(* A point exactly [meters] due north of [p]: with no change of longitude the
   haversine distance is exactly the great-circle arc, so
   [Places.distance_m p (north p meters) = meters] up to float rounding, far
   under the 1 mm allowance of [Places.within]. *)
let deg_per_m = 180. /. (Float.pi *. Places.earth_radius_m)

let north (p : Places.point) meters : Places.point =
  {p with lat = p.lat +. (meters *. deg_per_m)}

(* ---------- testables ---------- *)

let point =
  Alcotest.testable
    (fun f (p : Places.point) ->
      Format.fprintf f "{lat = %.9g; lon = %.9g}" p.lat p.lon)
    (fun (a : Places.point) b ->
      Float.abs (a.lat -. b.lat) < 1e-9 && Float.abs (a.lon -. b.lon) < 1e-9)

let point_opt = Alcotest.option point
let time_t = Alcotest.testable Ptime.pp Ptime.equal

let observation_id =
  Alcotest.testable
    (fun f id -> Format.pp_print_string f (Ids.Observation_id.to_string id))
    Ids.Observation_id.equal

(* [apply] gave [None]: nothing to save. *)
let nothing_to_save msg = function
  | None -> ()
  | Some (o' : Observation.t) ->
      Alcotest.failf "%s: expected nothing to save, got position %s" msg
        (match o'.position with
        | Some p -> Places.point_text (Places.of_position p)
        | None -> "none")

(* ---------- Move_plan.normalise ---------- *)

let normalise =
  Alcotest.test_case "normalise" `Quick (fun () ->
      let check msg expected (p : Places.point) =
        Alcotest.check point_opt msg expected (Move_plan.normalise p)
      in
      check "already in [-180, 180) and within 90: unchanged"
        (Some {lat = 48.0633; lon = 7.0081})
        {lat = 48.0633; lon = 7.0081};
      check "lon 190 wraps to -170"
        (Some {lat = 0.; lon = -170.})
        {lat = 0.; lon = 190.};
      check "lon -190 wraps to 170"
        (Some {lat = 0.; lon = 170.})
        {lat = 0.; lon = -190.};
      check "lon 180 wraps to -180 (the range is half-open at 180)"
        (Some {lat = 0.; lon = -180.})
        {lat = 0.; lon = 180.};
      check "lon -180 stays -180"
        (Some {lat = 0.; lon = -180.})
        {lat = 0.; lon = -180.};
      check "lon 540 (one and a half turns) wraps to -180"
        (Some {lat = 0.; lon = -180.})
        {lat = 0.; lon = 540.};
      check "lat 91 clamps to 90"
        (Some {lat = 90.; lon = 0.})
        {lat = 91.; lon = 0.};
      check "lat -91 clamps to -90"
        (Some {lat = -90.; lon = 0.})
        {lat = -91.; lon = 0.};
      check "a lon just under 180 that rounds up to 180 belongs to -180"
        (Some {lat = 0.; lon = -180.})
        {lat = 0.; lon = 179.9999996};
      (* Ties on lat: [wrap] moves a lon off its tie before rounding. *)
      check "rounds to 6 decimals, half away from zero, below the tie"
        (Some {lat = 48.063312; lon = 0.})
        {lat = 48.06331249; lon = 0.};
      check "rounds to 6 decimals, half away from zero, exactly on the tie"
        (Some {lat = 48.063313; lon = 0.})
        {lat = 48.0633125; lon = 0.};
      check "a negative tie rounds away from zero too"
        (Some {lat = -48.063313; lon = 0.})
        {lat = -48.0633125; lon = 0.};
      Alcotest.check point_opt "a nan latitude gives None" None
        (Move_plan.normalise {lat = Float.nan; lon = 0.});
      Alcotest.check point_opt "an infinite longitude gives None" None
        (Move_plan.normalise {lat = 0.; lon = Float.infinity}))

(* ---------- Move_plan.distance_text ---------- *)

let distance_text =
  Alcotest.test_case "distance_text" `Quick (fun () ->
      let check msg expected d =
        Alcotest.(check (option string))
          msg expected
          (Move_plan.distance_text d)
      in
      check "nan: no text" None Float.nan;
      check "infinity: no text" None Float.infinity;
      check "0.4 m rounds to 0: no visible move" None 0.4;
      check "0.5 m rounds up to 1 m" (Some "déplacé de 1 m") 0.5;
      check "96.2 m: whole metres" (Some "déplacé de 96 m") 96.2;
      check "999.4 m: still metres" (Some "déplacé de 999 m") 999.4;
      check "999.6 m: crosses into kilometres" (Some "déplacé de 1 km") 999.6;
      check "1049 m: 1 km, the decimal is dropped when 0"
        (Some "déplacé de 1 km") 1049.;
      check "1250 m: one decimal, French comma" (Some "déplacé de 1,3 km") 1250.;
      check "9949 m: still one decimal" (Some "déplacé de 9,9 km") 9949.;
      check "9950 m: whole kilometres from here on" (Some "déplacé de 10 km")
        9950.;
      check "12 400 m: whole kilometres" (Some "déplacé de 12 km") 12_400.)

(* ---------- Move_plan.meta ---------- *)

let meta =
  Alcotest.test_case "meta" `Quick (fun () ->
      let here = {Places.lat = 48.0633; lon = 7.0081} in
      Alcotest.(check string)
        "no origin: just the coordinates" "48.0633, 7.0081"
        (Move_plan.meta ~origin:None here);
      Alcotest.(check string)
        "origin equal to the centre: no suffix" "48.0633, 7.0081"
        (Move_plan.meta ~origin:(Some here) here);
      Alcotest.(check string)
        "origin 96 m away: the centre's coordinates, then the distance"
        "48.0642, 7.0081 · déplacé de 96 m"
        (Move_plan.meta ~origin:(Some here) (north here 96.));
      Alcotest.(check string)
        "lon 190 is wrapped before being printed to 4 decimals"
        "10.0000, -170.0000"
        (Move_plan.meta ~origin:None {lat = 10.; lon = 190.});
      Alcotest.(check string)
        "a wrapped copy of the origin is no move: no suffix"
        "10.0000, -170.0000"
        (Move_plan.meta
           ~origin:(Some {lat = 10.; lon = -170.})
           {lat = 10.; lon = 190.});
      Alcotest.(check string)
        "a point normalise rejects is printed raw, without a distance"
        "nan, 0.0000"
        (Move_plan.meta ~origin:(Some here) {lat = Float.nan; lon = 0.}))

(* ---------- Move_plan.title ---------- *)

let title =
  Alcotest.test_case "title" `Quick (fun () ->
      let centre = {Places.lat = 48.0633; lon = 7.0081} in
      let near = north centre 400. and far = north centre 600. in
      let on_the_edge = north centre Places.radius_m in
      Alcotest.(check string)
        "a picked result within 500 m of the centre wins over the origin"
        "Schlucht"
        (Move_plan.title ~origin:(Some near) ~origin_name:(Some "Lac Blanc")
           ~picked:(Some ("Schlucht", near))
           centre);
      Alcotest.(check string)
        "a picked result beyond 500 m: the origin's name wins instead"
        "Lac Blanc"
        (Move_plan.title ~origin:(Some near) ~origin_name:(Some "Lac Blanc")
           ~picked:(Some ("Schlucht", far))
           centre);
      Alcotest.(check string)
        "neither a pick nor a named origin: no name" "Lieu sans nom"
        (Move_plan.title ~origin:None ~origin_name:None ~picked:None centre);
      Alcotest.(check string)
        "the origin is within 500 m but has no name either: no name"
        "Lieu sans nom"
        (Move_plan.title ~origin:(Some near) ~origin_name:None ~picked:None
           centre);
      Alcotest.(check string)
        "exactly 500 m from the origin still counts as within it (inclusive)"
        "Lac Blanc"
        (Move_plan.title ~origin:(Some on_the_edge)
           ~origin_name:(Some "Lac Blanc") ~picked:None centre);
      Alcotest.(check string)
        "a named origin beyond 500 m: no name" "Lieu sans nom"
        (Move_plan.title ~origin:(Some far) ~origin_name:(Some "Lac Blanc")
           ~picked:None centre);
      Alcotest.(check string)
        "a pick and a named origin both beyond 500 m: no name" "Lieu sans nom"
        (Move_plan.title ~origin:(Some far) ~origin_name:(Some "Lac Blanc")
           ~picked:(Some ("Schlucht", far))
           centre))

(* ---------- Move_plan.can_validate ---------- *)

let can_validate =
  Alcotest.test_case "can_validate" `Quick (fun () ->
      Alcotest.(check bool)
        "at the minimum zoom: enabled" true
        (Move_plan.can_validate ~zoom:12.);
      Alcotest.(check bool)
        "just below the minimum: disabled" false
        (Move_plan.can_validate ~zoom:11.99);
      Alcotest.(check bool)
        "nan: disabled" false
        (Move_plan.can_validate ~zoom:Float.nan))

let constants =
  Alcotest.test_case "the camera constants are the documented literals" `Quick
    (fun () ->
      Alcotest.(check (float 0.)) "initial_zoom" 17. Move_plan.initial_zoom;
      Alcotest.(check (float 0.)) "search_zoom" 16. Move_plan.search_zoom;
      Alcotest.(check (float 0.)) "min_zoom" 12. Move_plan.min_zoom)

(* ---------- Move_plan.apply ---------- *)

let apply =
  Alcotest.test_case "apply" `Quick (fun () ->
      let origin = {Places.lat = 48.0633; lon = 7.0081} in
      let o =
        obs ~id:1 ~at:t1
          ~pos:{lat = origin.lat; lon = origin.lon; accuracy_m = Some 12.}
          ~plant:7 ~place_label:"Lac Blanc" ~place_derived:"Près de Schlucht"
          ~place_detail:"Pélégri" ~note:"une touffe" ()
      in
      nothing_to_save "the centre equals the origin, even with a stale accuracy"
        (Move_plan.apply o origin ~at:t2);
      let barely_moved = {origin with lat = 48.06330004} in
      nothing_to_save "the centre rounds to the same point as the origin"
        (Move_plan.apply o barely_moved ~at:t2);
      let moved_96m = north origin 96. in
      (match Move_plan.apply o moved_96m ~at:t2 with
      | None -> Alcotest.fail "a 96 m move has something to save"
      | Some o' ->
          let p =
            match o'.position with
            | Some p -> p
            | None -> Alcotest.fail "the moved observation keeps a position"
          in
          Alcotest.(check (float 1e-6))
            "lat follows the centre" moved_96m.lat p.lat;
          Alcotest.(check (float 1e-6))
            "lon follows the centre" moved_96m.lon p.lon;
          Alcotest.(check (option (float 0.)))
            "accuracy is cleared" None p.accuracy_m;
          Alcotest.(check (option string))
            "place_derived is cleared" None o'.place_derived;
          Alcotest.(check (option string))
            "place_detail is cleared alongside place_derived (the check \
             constraint rejects a detail without a derived name)"
            None o'.place_detail;
          Alcotest.(check (option string))
            "place_label is kept: still within 500 m of the origin"
            (Some "Lac Blanc") o'.place_label;
          Alcotest.check time_t "updated_at is the save time" t2 o'.updated_at;
          Alcotest.check observation_id "id is unchanged" o.id o'.id;
          Alcotest.(check (option string)) "note is unchanged" o.note o'.note;
          Alcotest.(check (option string))
            "plant_id is unchanged"
            (Some (id_string 7))
            (Option.map Ids.Plant_id.to_string o'.plant_id);
          Alcotest.check time_t "at is unchanged" o.at o'.at;
          Alcotest.check time_t "created_at is unchanged" o.created_at
            o'.created_at;
          Alcotest.(check (option time_t))
            "deleted_at is unchanged" o.deleted_at o'.deleted_at);
      (* Measured on the rounded centre: 499 m stays 499.04 m, within. *)
      (match Move_plan.apply o (north origin 499.) ~at:t2 with
      | None -> Alcotest.fail "a 499 m move has something to save"
      | Some o' ->
          Alcotest.(check (option string))
            "499 m: still the same place, place_label is kept"
            (Some "Lac Blanc") o'.place_label);
      (match Move_plan.apply o (north origin 501.) ~at:t2 with
      | None -> Alcotest.fail "a 501 m move has something to save"
      | Some o' ->
          Alcotest.(check (option string))
            "501 m: another place, place_label is cleared" None o'.place_label);
      let moved_2km = north origin 2000. in
      (match Move_plan.apply o moved_2km ~at:t2 with
      | None -> Alcotest.fail "a 2 km move has something to save"
      | Some o' ->
          Alcotest.(check (option string))
            "a 2 km move leaves the cluster: place_label is cleared" None
            o'.place_label);
      let unplaced = obs ~id:2 ~at:t1 ~place_label:"Ancien nom" () in
      (match Move_plan.apply unplaced origin ~at:t2 with
      | None ->
          Alcotest.fail "giving a position to an unplaced observation saves"
      | Some o' ->
          let p =
            match o'.position with
            | Some p -> p
            | None -> Alcotest.fail "the now-placed observation has a position"
          in
          Alcotest.(check (float 1e-6)) "the new lat" origin.lat p.lat;
          Alcotest.(check (float 1e-6)) "the new lon" origin.lon p.lon;
          Alcotest.(check (option (float 0.)))
            "accuracy_m is None" None p.accuracy_m;
          Alcotest.(check (option string))
            "there was no origin point to compare against: place_label cleared"
            None o'.place_label);
      (match Move_plan.apply unplaced {lat = 10.; lon = 190.} ~at:t2 with
      | None -> Alcotest.fail "a wrap-around move has something to save"
      | Some o' -> (
          match o'.position with
          | Some p ->
              Alcotest.(check (float 1e-6))
                "lon 190 is stored normalised to -170" (-170.) p.lon
          | None -> Alcotest.fail "the moved observation has a position"));
      nothing_to_save "a non-finite centre"
        (Move_plan.apply o {lat = Float.nan; lon = 7.0081} ~at:t2))

let () =
  Alcotest.run "move_plan"
    [
      ("constants", [constants]);
      ("can_validate", [can_validate]);
      ("normalise", [normalise]);
      ("distance_text", [distance_text]);
      ("meta", [meta]);
      ("title", [title]);
      ("apply", [apply]);
    ]
