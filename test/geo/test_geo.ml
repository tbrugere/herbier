(* Native checks of app/geo/features.ml and app/geo/style.ml. [web/map/liberty.json] doubles as the shipped
   style and the fixture of the with_overlays tests, read relative to the
   test's working directory ([_build/default/test/geo]). *)

module Features = Herbier_geo.Features
module Style = Herbier_geo.Style
module Observation = Herbier_domain.Observation
module Places = Herbier_domain.Places
module Ids = Herbier_domain.Ids
module Testable = Herbier_test_support.Testable
module Text = Herbier_test_support.Text

(* ---------- building test observations ---------- *)

(* Zero-padded, as test/domain/test_places.ml does, so ids compare in the
   order of [n]. *)
let id_string n = Printf.sprintf "00000000-0000-4000-8000-%012d" n

let obs_id n =
  match Ids.Observation_id.of_string (id_string n) with
  | Some id -> id
  | None -> Alcotest.failf "Observation_id.of_string %S gave None" (id_string n)

let plant_id n =
  match Ids.Plant_id.of_string (id_string n) with
  | Some id -> id
  | None -> Alcotest.failf "Plant_id.of_string %S gave None" (id_string n)

let base_time = 1_700_000_000.

let time s =
  match Ptime.of_float_s (base_time +. float_of_int s) with
  | Some t -> t
  | None -> Alcotest.failf "Ptime.of_float_s rejected offset %d" s

(* [obs ?plant ?(deleted=false) ~id ~at pos]: an observation with id number
   [id], taken [at] seconds after [base_time], at [pos] (lat, lon). *)
let obs ?plant ?(deleted = false) ~id ~at pos : Observation.t =
  let at = time at in
  {
    Observation.id = obs_id id;
    plant_id = plant;
    at;
    position =
      Option.map
        (fun (lat, lon) -> {Observation.lat; lon; accuracy_m = None})
        pos;
    place_label = None;
    place_derived = None;
    place_detail = None;
    note = None;
    created_at = at;
    updated_at = at;
    deleted_at = (if deleted then Some at else None);
  }

let string_of_id (o : Observation.t) = Ids.Observation_id.to_string o.id

(* Unplaceable observations shared by several suites: no position, deleted,
   nan and infinite coordinates (same shape as test_places.ml's [unplaceable]). *)
let no_position = obs ~id:90 ~at:0 None
let deleted = obs ~id:91 ~at:1 ~deleted:true (Some (48.1, 7.2))
let nan_lat = obs ~id:92 ~at:2 (Some (Float.nan, 7.2))
let inf_lon = obs ~id:93 ~at:3 (Some (48.1, Float.infinity))
let unplaceable = [no_position; deleted; nan_lat; inf_lon]

(* ---------- testables ---------- *)

let bounds =
  let pp f (b : Features.bounds) =
    Format.fprintf f "{south = %.9g; west = %.9g; north = %.9g; east = %.9g}"
      b.south b.west b.north b.east
  in
  let equal (a : Features.bounds) (b : Features.bounds) =
    Float.equal a.south b.south
    && Float.equal a.west b.west
    && Float.equal a.north b.north
    && Float.equal a.east b.east
  in
  Alcotest.testable pp equal

let style_error =
  let pp f = function
    | Style.Not_a_style key -> Format.fprintf f "Not_a_style %S" key
    | Style.Duplicate_id id -> Format.fprintf f "Duplicate_id %S" id
  in
  let equal a b =
    match (a, b) with
    | Style.Not_a_style a, Style.Not_a_style b -> String.equal a b
    | Style.Duplicate_id a, Style.Duplicate_id b -> String.equal a b
    | Style.Not_a_style _, Style.Duplicate_id _
    | Style.Duplicate_id _, Style.Not_a_style _ ->
        false
  in
  Alcotest.testable pp equal

let pp_point f (p : Places.point) =
  Format.fprintf f "{lat = %.12g; lon = %.12g}" p.lat p.lon

let close_point (a : Places.point) (b : Places.point) =
  Float.abs (a.lat -. b.lat) <= 1e-9 && Float.abs (a.lon -. b.lon) <= 1e-9

let point = Alcotest.testable pp_point close_point

let pp_hit f = function
  | Features.Group (b : Features.bounds) ->
      Format.fprintf f
        "Group {south = %.9g; west = %.9g; north = %.9g; east = %.9g}" b.south
        b.west b.north b.east
  | Features.Member id ->
      Format.fprintf f "Member %s" (Ids.Observation_id.to_string id)

let equal_hit a b =
  match (a, b) with
  | Features.Group (a : Features.bounds), Features.Group (b : Features.bounds)
    ->
      Float.equal a.south b.south
      && Float.equal a.west b.west
      && Float.equal a.north b.north
      && Float.equal a.east b.east
  | Features.Member a, Features.Member b -> Ids.Observation_id.equal a b
  | Features.Group _, Features.Member _ | Features.Member _, Features.Group _ ->
      false

let hit_t = Alcotest.testable pp_hit equal_hit

(* ---------- small JSON helpers ---------- *)

let collection features =
  `Assoc [("type", `String "FeatureCollection"); ("features", `List features)]

let point_feature ~id ~lon ~lat ~kind =
  `Assoc
    [
      ("type", `String "Feature");
      ( "geometry",
        `Assoc
          [
            ("type", `String "Point");
            ("coordinates", `List [`Float lon; `Float lat]);
          ] );
      ("properties", `Assoc [("id", `String id); ("kind", `String kind)]);
    ]

let ids_of (j : Yojson.Safe.t) : string list =
  let open Yojson.Safe.Util in
  j
  |> member "features"
  |> to_list
  |> List.map (fun f -> f |> member "properties" |> member "id" |> to_string)

(* ---------- Features.observations ---------- *)

let observations_empty_is_the_empty_collection () =
  Alcotest.(check Testable.yojson)
    "Features.observations [] equals Features.empty" Features.empty
    (Features.observations []);
  Alcotest.(check Testable.yojson)
    "Features.empty is the empty FeatureCollection" (collection [])
    Features.empty

let observations_identified () =
  let o = obs ~id:1 ~at:0 ~plant:(plant_id 1) (Some (48.1, 7.2)) in
  Alcotest.(check Testable.yojson)
    "one feature, lon before lat, kind identified"
    (collection
       [
         point_feature ~id:(string_of_id o) ~lon:7.2 ~lat:48.1 ~kind:"identified";
       ])
    (Features.observations [o])

let observations_to_identify () =
  let o = obs ~id:1 ~at:0 (Some (48.1, 7.2)) in
  Alcotest.(check Testable.yojson)
    "no plant_id gives kind to_identify"
    (collection
       [
         point_feature ~id:(string_of_id o) ~lon:7.2 ~lat:48.1
           ~kind:"to_identify";
       ])
    (Features.observations [o])

let observations_unplaceable_absent () =
  let placeable = obs ~id:1 ~at:0 (Some (48.1, 7.2)) in
  let result = Features.observations (unplaceable @ [placeable]) in
  let open Yojson.Safe.Util in
  Alcotest.(check int)
    "only the placeable observation gives a feature" 1
    (result |> member "features" |> to_list |> List.length);
  Alcotest.(check (list string))
    "the feature is the placeable one"
    [string_of_id placeable]
    (ids_of result)

let observations_order_ascending_at () =
  let newest = obs ~id:1 ~at:2 (Some (48.0, 7.0)) in
  let middle = obs ~id:2 ~at:1 (Some (48.1, 7.1)) in
  let oldest = obs ~id:3 ~at:0 (Some (48.2, 7.2)) in
  let expected_ids = List.map string_of_id [oldest; middle; newest] in
  List.iter
    (fun (name, input) ->
      Alcotest.(check (list string))
        (Printf.sprintf "%s comes out ascending by at" name)
        expected_ids
        (ids_of (Features.observations input)))
    [
      ("newest-first input", [newest; middle; oldest]);
      ("already-ascending input", [oldest; middle; newest]);
      ("middle-first input", [middle; oldest; newest]);
    ]

let observations_order_tie_by_id () =
  let a = obs ~id:1 ~at:0 (Some (48.0, 7.0)) in
  let b = obs ~id:2 ~at:0 (Some (48.1, 7.1)) in
  let expected_ids = List.map string_of_id [a; b] in
  Alcotest.(check (list string))
    "equal at: ascending by id although b is given first" expected_ids
    (ids_of (Features.observations [b; a]));
  Alcotest.(check (list string))
    "same with a given first" expected_ids
    (ids_of (Features.observations [a; b]))

let observations_round_trips_through_json_text () =
  let o1 = obs ~id:1 ~at:0 ~plant:(plant_id 1) (Some (48.1, 7.2)) in
  let o2 = obs ~id:2 ~at:1 (Some (48.2, 7.3)) in
  let result = Features.observations (unplaceable @ [o1; o2]) in
  let text = Yojson.Safe.to_string result in
  Alcotest.(check bool)
    "the serialised text never spells out nan or inf" false
    (let lower = String.lowercase_ascii text in
     Text.contains ~sub:"nan" lower || Text.contains ~sub:"inf" lower);
  Alcotest.(check Testable.yojson)
    "parsing the text back gives an equal value" result
    (Yojson.Safe.from_string text)

(* ---------- Features.bounds ---------- *)

let bounds_none_for_empty_or_unplaceable () =
  Alcotest.(check (option bounds)) "[] has no bounds" None (Features.bounds []);
  Alcotest.(check (option bounds))
    "all-unplaceable has no bounds" None
    (Features.bounds unplaceable)

let bounds_one_point () =
  let o = obs ~id:1 ~at:0 (Some (48.1, 7.2)) in
  Alcotest.(check (option bounds))
    "south = north, west = east"
    (Some {Features.south = 48.1; west = 7.2; north = 48.1; east = 7.2})
    (Features.bounds [o])

let bounds_three_points_ignore_unplaceable () =
  let a = obs ~id:1 ~at:0 (Some (48.0, 7.0)) in
  let b = obs ~id:2 ~at:1 (Some (49.0, 6.0)) in
  let c = obs ~id:3 ~at:2 (Some (47.5, 8.0)) in
  let extreme = obs ~id:4 ~at:3 ~deleted:true (Some (90., 180.)) in
  Alcotest.(check (option bounds))
    "min/max per axis; the deleted extreme point is ignored"
    (Some {Features.south = 47.5; west = 6.0; north = 49.0; east = 8.0})
    (Features.bounds [a; b; c; extreme])

(* ---------- Features.circle ---------- *)

let ring_of (j : Yojson.Safe.t) : (float * float) list =
  let open Yojson.Safe.Util in
  match j |> member "features" |> to_list with
  | [feature] -> (
      match feature |> member "geometry" |> member "coordinates" |> to_list with
      | [ring] ->
          ring
          |> to_list
          |> List.map (fun pos ->
              match pos |> to_list with
              | [lon; lat] -> (to_number lon, to_number lat)
              | _ -> Alcotest.fail "a ring vertex is not [lon, lat]")
      | _ -> Alcotest.fail "the polygon does not have exactly one ring")
  | _ -> Alcotest.fail "the circle does not have exactly one feature"

let centre : Places.point = {lat = 48.06; lon = 7.0}

let circle_shape () =
  let ring =
    ring_of (Features.circle ~center:centre ~radius_m:1000. ~steps:64)
  in
  Alcotest.(check int) "a 64-step ring has 65 positions" 65 (List.length ring);
  Alcotest.(check (pair (float 0.) (float 0.)))
    "the last position equals the first" (List.hd ring) (List.nth ring 64)

let circle_vertices_are_at_radius () =
  List.iter
    (fun radius_m ->
      let ring = ring_of (Features.circle ~center:centre ~radius_m ~steps:64) in
      List.iteri
        (fun i (lon, lat) ->
          let d = Places.distance_m centre {Places.lat; lon} in
          Alcotest.(check (float 0.01))
            (Printf.sprintf "vertex %d is radius_m=%g from the centre" i
               radius_m)
            radius_m d)
        ring)
    [25.; 5000.]

let circle_bearings () =
  let ring =
    ring_of (Features.circle ~center:centre ~radius_m:1000. ~steps:64)
  in
  let lon0, lat0 = List.nth ring 0 in
  Alcotest.(check (float 1e-9))
    "vertex 0 keeps the centre's longitude" centre.lon lon0;
  Alcotest.(check bool)
    "vertex 0 is north of the centre" true (lat0 > centre.lat);
  let lon16, lat16 = List.nth ring 16 in
  Alcotest.(check bool)
    "vertex 16 of 64 is east of the centre" true (lon16 > centre.lon);
  Alcotest.(check (float 1e-4))
    "vertex 16 of 64 is close to the centre's latitude" centre.lat lat16

let circle_empty_on_invalid_input () =
  List.iter
    (fun (name, radius_m) ->
      Alcotest.(check Testable.yojson)
        name Features.empty
        (Features.circle ~center:centre ~radius_m ~steps:64))
    [
      ("radius 0 gives empty", 0.);
      ("negative radius gives empty", -1.);
      ("nan radius gives empty", Float.nan);
      ("infinite radius gives empty", Float.infinity);
    ];
  Alcotest.(check Testable.yojson)
    "fewer than 3 steps gives empty" Features.empty
    (Features.circle ~center:centre ~radius_m:1000. ~steps:2);
  List.iter
    (fun (name, center) ->
      Alcotest.(check Testable.yojson)
        name Features.empty
        (Features.circle ~center ~radius_m:1000. ~steps:64))
    [
      ("a nan latitude gives empty", {Places.lat = Float.nan; lon = 7.0});
      ("an infinite latitude gives empty", {lat = Float.infinity; lon = 7.0});
      ("a nan longitude gives empty", {lat = 48.; lon = Float.nan});
      ("an infinite longitude gives empty", {lat = 48.; lon = Float.infinity});
    ]

let circle_three_steps () =
  let ring =
    ring_of (Features.circle ~center:centre ~radius_m:1000. ~steps:3)
  in
  Alcotest.(check int) "a 3-step ring has 4 positions" 4 (List.length ring);
  Alcotest.(check (pair (float 0.) (float 0.)))
    "the last position equals the first" (List.hd ring) (List.nth ring 3)

let circle_at_the_pole () =
  let ring =
    ring_of
      (Features.circle
         ~center:{lat = 88.302683353501408; lon = 0.}
         ~radius_m:188733. ~steps:64)
  in
  List.iteri
    (fun i (lon, lat) ->
      Alcotest.(check bool)
        (Printf.sprintf "vertex %d is finite" i)
        true
        (Float.is_finite lon && Float.is_finite lat))
    ring

(* ---------- Features.circle_bounds ---------- *)

let circle_bounds_matches_circle_ring_extremes () =
  let center : Places.point = {lat = 45.; lon = 3.} in
  let radius_m = 1000. in
  let ring =
    ring_of (Features.circle ~center ~radius_m ~steps:Features.circle_steps)
  in
  let lats = List.map snd ring and lons = List.map fst ring in
  let expected : Features.bounds =
    {
      south = List.fold_left Float.min Float.infinity lats;
      north = List.fold_left Float.max Float.neg_infinity lats;
      west = List.fold_left Float.min Float.infinity lons;
      east = List.fold_left Float.max Float.neg_infinity lons;
    }
  in
  match Features.circle_bounds ~center ~radius_m with
  | None -> Alcotest.fail "circle_bounds gave None for a valid circle"
  | Some b ->
      Alcotest.(check bounds)
        "south/west/north/east equal the ring's min/max" expected b

let circle_bounds_degree_approximation () =
  let center : Places.point = {lat = 45.; lon = 3.} in
  match Features.circle_bounds ~center ~radius_m:1000. with
  | None -> Alcotest.fail "circle_bounds gave None"
  | Some b ->
      let half_span_deg = 1000. /. 6_371_000. *. 180. /. Float.pi in
      Alcotest.(check (float 1e-6))
        "north - lat is about 1000 m in degrees" half_span_deg
        (b.north -. center.lat);
      Alcotest.(check (float 1e-6))
        "lat - south is the same" half_span_deg (center.lat -. b.south);
      Alcotest.(check (float 1e-4))
        "the lon half-span widens by 1 / cos(lat)"
        (half_span_deg /. Float.cos (center.lat *. Float.pi /. 180.))
        ((b.east -. b.west) /. 2.)

let circle_bounds_symmetric_at_equator () =
  match
    Features.circle_bounds ~center:{Places.lat = 0.; lon = 0.} ~radius_m:500.
  with
  | None -> Alcotest.fail "circle_bounds gave None"
  | Some b ->
      Alcotest.(check (float 1e-12)) "north equals -south" (-.b.south) b.north;
      Alcotest.(check (float 1e-12)) "east equals -west" (-.b.west) b.east

let circle_bounds_lon_span_widens_with_latitude () =
  match
    Features.circle_bounds ~center:{Places.lat = 60.; lon = 0.} ~radius_m:1000.
  with
  | None -> Alcotest.fail "circle_bounds gave None"
  | Some b ->
      let lat_half = b.north -. 60. in
      let lon_half = (b.east -. b.west) /. 2. in
      Alcotest.(check (float 0.05))
        "the lon half-span is about twice the lat half-span at lat 60" 2.
        (lon_half /. lat_half)

let circle_bounds_contains_the_centre () =
  List.iter
    (fun (center : Places.point) ->
      match Features.circle_bounds ~center ~radius_m:200. with
      | None -> Alcotest.fail "circle_bounds gave None for a valid centre"
      | Some b -> (
          match
            b.south < center.lat
            && center.lat < b.north
            && b.west < center.lon
            && center.lon < b.east
          with
          | true -> ()
          | false ->
              Alcotest.failf
                "(%g, %g) is not strictly inside south %g west %g north %g \
                 east %g"
                center.lat center.lon b.south b.west b.north b.east))
    [
      {Places.lat = 45.; lon = 3.};
      {Places.lat = -20.; lon = 170.};
      {Places.lat = 0.; lon = 0.};
    ]

let circle_bounds_contiguous_across_the_antimeridian () =
  match
    Features.circle_bounds
      ~center:{Places.lat = 0.; lon = 179.9999}
      ~radius_m:30.
  with
  | None -> Alcotest.fail "circle_bounds gave None"
  | Some b ->
      Alcotest.(check bool)
        (Printf.sprintf "east %g is past 180, not wrapped" b.east)
        true (b.east > 180.);
      Alcotest.(check bool)
        (Printf.sprintf "the box is narrow (west %g, east %g)" b.west b.east)
        true
        (b.east -. b.west < 0.001)

let circle_bounds_none_on_invalid_input () =
  let center : Places.point = {lat = 45.; lon = 3.} in
  List.iter
    (fun (name, radius_m) ->
      Alcotest.(check (option bounds))
        name None
        (Features.circle_bounds ~center ~radius_m))
    [
      ("radius 0 gives None", 0.);
      ("negative radius gives None", -1.);
      ("nan radius gives None", Float.nan);
      ("infinite radius gives None", Float.infinity);
    ];
  List.iter
    (fun (name, center) ->
      Alcotest.(check (option bounds))
        name None
        (Features.circle_bounds ~center ~radius_m:1000.))
    [
      ("a nan latitude gives None", {Places.lat = Float.nan; lon = 3.});
      ( "an infinite latitude gives None",
        {Places.lat = Float.infinity; lon = 3.} );
      ("a nan longitude gives None", {Places.lat = 45.; lon = Float.nan});
      ( "an infinite longitude gives None",
        {Places.lat = 45.; lon = Float.infinity} );
    ]

(* ---------- Features.accuracy_bounds ---------- *)

let position lat lon accuracy_m : Observation.position = {lat; lon; accuracy_m}

let accuracy_bounds_matches_circle_bounds () =
  let pos = position 45.7712 3.0823 (Some 12.5) in
  let expected =
    Features.circle_bounds
      ~center:{Places.lat = pos.lat; lon = pos.lon}
      ~radius_m:12.5
  in
  Alcotest.(check (option bounds))
    "a positive finite accuracy equals circle_bounds at that radius" expected
    (Features.accuracy_bounds pos)

let accuracy_bounds_degenerate_box () =
  List.iter
    (fun (name, accuracy_m) ->
      let pos = position 45.1 7.2 accuracy_m in
      Alcotest.(check (option bounds))
        name
        (Some {Features.south = 45.1; west = 7.2; north = 45.1; east = 7.2})
        (Features.accuracy_bounds pos))
    [
      ("accuracy None collapses to the point", None);
      ("accuracy 0 collapses to the point", Some 0.);
      ("negative accuracy collapses to the point", Some (-3.));
      ("nan accuracy collapses to the point", Some Float.nan);
      ("infinite accuracy collapses to the point", Some Float.infinity);
    ]

let accuracy_bounds_none_on_nonfinite_position () =
  Alcotest.(check (option bounds))
    "nan latitude gives None" None
    (Features.accuracy_bounds (position Float.nan 7.2 (Some 5.)));
  Alcotest.(check (option bounds))
    "infinite longitude gives None" None
    (Features.accuracy_bounds (position 45.1 Float.infinity (Some 5.)));
  Alcotest.(check (option bounds))
    "nan latitude without accuracy gives None" None
    (Features.accuracy_bounds (position Float.nan 7.2 None));
  Alcotest.(check (option bounds))
    "infinite longitude without accuracy gives None" None
    (Features.accuracy_bounds (position 45.1 Float.infinity None));
  Alcotest.(check (option bounds))
    "nan latitude with a zero accuracy gives None" None
    (Features.accuracy_bounds (position Float.nan 7.2 (Some 0.)))

(* ---------- Features.focus ---------- *)

let focus_none_is_empty () =
  Alcotest.(check Testable.yojson)
    "None gives Features.empty" Features.empty (Features.focus None)

let focus_some_is_a_lone_point_feature_with_no_properties () =
  let p : Places.point = {lat = 45.7712; lon = 3.0823} in
  Alcotest.(check Testable.yojson)
    "exactly the documented FeatureCollection, lon before lat"
    (collection
       [
         `Assoc
           [
             ("type", `String "Feature");
             ( "geometry",
               `Assoc
                 [
                   ("type", `String "Point");
                   ("coordinates", `List [`Float p.lon; `Float p.lat]);
                 ] );
             ("properties", `Assoc []);
           ];
       ])
    (Features.focus (Some p))

let focus_nonfinite_coordinate_is_empty () =
  Alcotest.(check Testable.yojson)
    "a nan latitude gives empty" Features.empty
    (Features.focus (Some {Places.lat = Float.nan; lon = 3.}));
  Alcotest.(check Testable.yojson)
    "an infinite longitude gives empty" Features.empty
    (Features.focus (Some {Places.lat = 45.; lon = Float.infinity}))

(* ---------- Features.places, find, place_points, selection, hit ---------- *)

(* Three spots well over 500 m apart (app/store/dev_seed.ml's lisiere, jardin,
   ruisseau; the 500 m rule is architecture §8),
   so [Places.cluster] gives three places; members of the same spot share its
   point, so each cluster's extent collapses to that point and its bounds are
   that single point. Ascending [at] (0..5) across the 3 spots so
   [Places.cluster] orders the places A, B, C. *)

let spot_a : Places.point = {lat = 45.7712; lon = 3.0823}
let spot_b : Places.point = {lat = 45.7650; lon = 3.0901}
let spot_c : Places.point = {lat = 45.7801; lon = 3.0711}
let at_spot (p : Places.point) = (p.lat, p.lon)

(* Cluster A: 3 members, mixed identified (2 of 3); cluster B: 1 member,
   unidentified; cluster C: 2 members, mixed identified (1 of 2). *)
let a1 = obs ~id:21 ~at:0 (Some (at_spot spot_a))
let a2 = obs ~id:22 ~at:1 ~plant:(plant_id 1) (Some (at_spot spot_a))
let a3 = obs ~id:23 ~at:2 ~plant:(plant_id 2) (Some (at_spot spot_a))
let b1 = obs ~id:24 ~at:3 (Some (at_spot spot_b))
let c1 = obs ~id:25 ~at:4 ~plant:(plant_id 3) (Some (at_spot spot_c))
let c2 = obs ~id:26 ~at:5 (Some (at_spot spot_c))
let three_spots = [a1; a2; a3; b1; c1; c2]
let always_true (_ : Places.cluster) (_ : Observation.t) = true
let key_string (p : Features.place) = Ids.Observation_id.to_string p.key
let member_ids (p : Features.place) = List.map string_of_id p.cluster.members
let shown_ids (p : Features.place) = List.map string_of_id p.shown

let places_everything () =
  let places = Features.places ~keep:always_true three_spots in
  Alcotest.(check (list string))
    "key is each cluster's earliest member's id"
    [string_of_id a1; string_of_id b1; string_of_id c1]
    (List.map key_string places);
  Alcotest.(check (list (list string)))
    "shown is the whole cluster when keep is always true"
    [
      List.map string_of_id [a1; a2; a3];
      [string_of_id b1];
      List.map string_of_id [c1; c2];
    ]
    (List.map shown_ids places);
  Alcotest.(check (list (list string)))
    "cluster.members mirrors shown here"
    (List.map shown_ids places)
    (List.map member_ids places)

let places_whole_cluster_dropped () =
  let keep (_ : Places.cluster) (o : Observation.t) =
    not (Ids.Observation_id.equal o.id b1.id)
  in
  let everything = Features.places ~keep:always_true three_spots in
  let places = Features.places ~keep three_spots in
  Alcotest.(check (list string))
    "B is absent, A and C remain in order"
    [string_of_id a1; string_of_id c1]
    (List.map key_string places);
  let cluster_of key ps =
    List.find (fun (p : Features.place) -> String.equal (key_string p) key) ps
  in
  List.iter
    (fun key ->
      let before = cluster_of key everything
      and after = cluster_of key places in
      Alcotest.(check (list string))
        (Printf.sprintf "%s's cluster.members is unchanged" key)
        (member_ids before) (member_ids after);
      Alcotest.(check point)
        (Printf.sprintf "%s's centroid is unchanged" key)
        before.cluster.centroid after.cluster.centroid)
    [string_of_id a1; string_of_id c1]

let places_earliest_member_dropped () =
  let keep (_ : Places.cluster) (o : Observation.t) =
    not (Ids.Observation_id.equal o.id a1.id)
  in
  let places = Features.places ~keep three_spots in
  let a =
    match
      List.find_opt
        (fun (p : Features.place) -> Ids.Observation_id.equal p.key a1.id)
        places
    with
    | Some p -> p
    | None ->
        Alcotest.fail "place A is missing although 2 of its 3 members pass"
  in
  Alcotest.(check string)
    "key is still A1's id" (string_of_id a1) (key_string a);
  Alcotest.(check (list string))
    "shown is A without A1"
    (List.map string_of_id [a2; a3])
    (shown_ids a)

let places_keep_sees_the_cluster () =
  let keep (c : Places.cluster) (_ : Observation.t) =
    List.length c.members >= 2
  in
  let places = Features.places ~keep three_spots in
  Alcotest.(check (list string))
    "only the clusters with >= 2 members (A, C)"
    [string_of_id a1; string_of_id c1]
    (List.map key_string places)

let places_unplaceable_and_empty () =
  Alcotest.(check (list string))
    "no place for unplaceable observations" []
    (List.map key_string (Features.places ~keep:always_true unplaceable));
  Alcotest.(check (list string))
    "no place for an empty input" []
    (List.map key_string (Features.places ~keep:always_true []))

let find_by_any_member () =
  let places = Features.places ~keep:always_true three_spots in
  Alcotest.(check bool)
    "finds by the key (earliest member)" true
    (Option.is_some (Features.find places a1.id));
  Alcotest.(check bool)
    "finds by a non-earliest member" true
    (Option.is_some (Features.find places a3.id));
  let keep (_ : Places.cluster) (o : Observation.t) =
    not (Ids.Observation_id.equal o.id a3.id)
  in
  let filtered = Features.places ~keep three_spots in
  Alcotest.(check bool)
    "finds by a member filtered out of shown, through cluster.members" true
    (Option.is_some (Features.find filtered a3.id))

let find_absent () =
  let places = Features.places ~keep:always_true three_spots in
  Alcotest.(check bool)
    "unknown id" false
    (Option.is_some (Features.find places (obs_id 999)));
  Alcotest.(check bool)
    "an unplaceable observation's id" false
    (Option.is_some (Features.find places no_position.id))

let place_points_props (j : Yojson.Safe.t) =
  let open Yojson.Safe.Util in
  j
  |> member "features"
  |> to_list
  |> List.map (fun f ->
      let p = f |> member "properties" in
      ( p |> member "id" |> to_string,
        p |> member "count" |> to_int,
        p |> member "identified" |> to_int ))

let place_points_order_and_counts () =
  let places = Features.places ~keep:always_true three_spots in
  let json = Features.place_points places in
  Alcotest.(check (list string))
    "one feature per place, in order"
    (List.map key_string places)
    (List.map (fun (id, _, _) -> id) (place_points_props json));
  Alcotest.(check (list (pair int int)))
    "count/identified: A mixed 3/2, B all-unidentified 1/0, C mixed 2/1"
    [(3, 2); (1, 0); (2, 1)]
    (List.map (fun (_, c, i) -> (c, i)) (place_points_props json))

let place_points_properties_are_exact () =
  let places = Features.places ~keep:always_true three_spots in
  let json = Features.place_points places in
  let open Yojson.Safe.Util in
  match (places, json |> member "features" |> to_list) with
  | a :: _, first :: _ ->
      Alcotest.(check Testable.yojson)
        "A's feature has exactly id, count, identified, west, south, east, \
         north"
        (`Assoc
           [
             ("id", `String (key_string a));
             ("count", `Int 3);
             ("identified", `Int 2);
             ("west", `Float spot_a.lon);
             ("south", `Float spot_a.lat);
             ("east", `Float spot_a.lon);
             ("north", `Float spot_a.lat);
           ])
        (first |> member "properties");
      Alcotest.(check Testable.yojson)
        "geometry is a Point at the centroid"
        (`Assoc
           [
             ("type", `String "Point");
             ("coordinates", `List [`Float spot_a.lon; `Float spot_a.lat]);
           ])
        (first |> member "geometry")
  | _ -> Alcotest.fail "expected at least one place and one feature"

let place_points_empty_for_no_places () =
  Alcotest.(check Testable.yojson)
    "[] gives Features.empty" Features.empty (Features.place_points [])

(* One place whose two members are about 110 m apart: west/east and
   south/north differ, and the centroid is neither member. Kept out of
   [three_spots] so the order and count tests above stay as they are. *)
let d1 = obs ~id:31 ~at:10 (Some (45.7900, 3.0600))
let d2 = obs ~id:32 ~at:11 ~plant:(plant_id 4) (Some (45.7905, 3.0612))
let close_pair = [d1; d2]

let number_prop key f =
  Yojson.Safe.Util.(f |> member "properties" |> member key |> to_number)

let coordinates f =
  Yojson.Safe.Util.(
    f
    |> member "geometry"
    |> member "coordinates"
    |> to_list
    |> List.map to_number)

let only_feature json =
  match Yojson.Safe.Util.(json |> member "features" |> to_list) with
  | [f] -> f
  | l -> Alcotest.failf "expected one feature, got %d" (List.length l)

let place_points_bounds_and_centroid () =
  let close = Alcotest.float 1e-9 in
  let mean = ((45.7900 +. 45.7905) /. 2., (3.0600 +. 3.0612) /. 2.) in
  let f =
    only_feature
      (Features.place_points (Features.places ~keep:always_true close_pair))
  in
  List.iter
    (fun (key, expected) ->
      Alcotest.check close key expected (number_prop key f))
    [("west", 3.0600); ("south", 45.7900); ("east", 3.0612); ("north", 45.7905)];
  Alcotest.(check (list (float 1e-9)))
    "the point is the centroid, the members' mean"
    [snd mean; fst mean]
    (coordinates f);
  (* With d1 hidden, the bounds shrink to d2 but the place stays where the
     whole cluster is. *)
  let keep (_ : Places.cluster) (o : Observation.t) =
    not (Ids.Observation_id.equal o.id d1.id)
  in
  let f =
    only_feature (Features.place_points (Features.places ~keep close_pair))
  in
  List.iter
    (fun (key, expected) ->
      Alcotest.check close (key ^ " from shown") expected (number_prop key f))
    [
      ("west", 3.0612);
      ("south", 45.7905);
      ("east", 3.0612);
      ("north", 45.7905);
      ("count", 1.);
      ("identified", 1.);
    ];
  Alcotest.(check (list (float 1e-9)))
    "the point is still the whole cluster's centroid"
    [snd mean; fst mean]
    (coordinates f)

let place_points_and_selection_follow_shown () =
  let keep (_ : Places.cluster) (o : Observation.t) =
    not (Ids.Observation_id.equal o.id a2.id)
  in
  let places = Features.places ~keep three_spots in
  Alcotest.(check (list (pair int int)))
    "A counts a1 and a3 only (1 identified); B and C unchanged"
    [(2, 1); (1, 0); (2, 1)]
    (List.map
       (fun (_, c, i) -> (c, i))
       (place_points_props (Features.place_points places)));
  let open Yojson.Safe.Util in
  let ids =
    Features.selection (Some (List.hd places))
    |> member "features"
    |> to_list
    |> List.map (fun f -> f |> member "properties" |> member "id" |> to_string)
  in
  Alcotest.(check (list string))
    "the selection is A's place, then its shown members a1 and a3"
    [string_of_id a1; string_of_id a1; string_of_id a3]
    ids

let selection_none_is_empty () =
  Alcotest.(check Testable.yojson)
    "None gives Features.empty" Features.empty (Features.selection None)

let selection_some () =
  let places = Features.places ~keep:always_true three_spots in
  let a = List.hd places in
  let json = Features.selection (Some a) in
  let open Yojson.Safe.Util in
  let features = json |> member "features" |> to_list in
  Alcotest.(check int)
    "one place feature plus one per shown member" 4 (List.length features);
  let first = List.hd features in
  Alcotest.(check Testable.yojson)
    "first feature: role place, id = key, at the centroid"
    (`Assoc [("id", `String (key_string a)); ("role", `String "place")])
    (first |> member "properties");
  Alcotest.(check Testable.yojson)
    "first feature's geometry is the centroid"
    (`Assoc
       [
         ("type", `String "Point");
         ("coordinates", `List [`Float spot_a.lon; `Float spot_a.lat]);
       ])
    (first |> member "geometry");
  let members = List.tl features in
  Alcotest.(check (list string))
    "member features in compare_obs order (ascending at)"
    (List.map string_of_id [a1; a2; a3])
    (List.map
       (fun f -> f |> member "properties" |> member "id" |> to_string)
       members);
  List.iter
    (fun f ->
      Alcotest.(check (list string))
        "a member feature has exactly id and role" ["id"; "role"]
        (f |> member "properties" |> to_assoc |> List.map fst);
      Alcotest.(check string)
        "role is member" "member"
        (f |> member "properties" |> member "role" |> to_string);
      Alcotest.(check Testable.yojson)
        "a member feature is a Point at its observation's position (spot A)"
        (`Assoc
           [
             ("type", `String "Point");
             ("coordinates", `List [`Float spot_a.lon; `Float spot_a.lat]);
           ])
        (f |> member "geometry"))
    members

let group_props ?(west = `Float 3.07) ?(south = `Float 45.76)
    ?(east = `Float 3.09) ?(north = `Float 45.78) () =
  `Assoc
    [
      ("cluster", `Bool true);
      ("cluster_id", `Int 3);
      ("point_count", `Int 2);
      ("count", `Int 5);
      ("identified", `Int 4);
      ("west", west);
      ("south", south);
      ("east", east);
      ("north", north);
    ]

let hit_group () =
  Alcotest.(check (option hit_t))
    "float bounds give Group"
    (Some
       (Features.Group
          {Features.south = 45.76; west = 3.07; north = 45.78; east = 3.09}))
    (Features.hit (group_props ()));
  Alcotest.(check (option hit_t))
    "an integer bound gives Group with floats"
    (Some
       (Features.Group
          {Features.south = 45.76; west = 3.; north = 45.78; east = 3.09}))
    (Features.hit (group_props ~west:(`Int 3) ()))

let hit_group_missing_or_nonfinite_bound () =
  Alcotest.(check (option hit_t))
    "cluster:true without north is None" None
    (Features.hit
       (`Assoc
          [
            ("cluster", `Bool true);
            ("west", `Float 3.07);
            ("south", `Float 45.76);
            ("east", `Float 3.09);
          ]));
  Alcotest.(check (option hit_t))
    "cluster:true with a nan bound is None" None
    (Features.hit (group_props ~south:(`Float Float.nan) ()))

let hit_member () =
  let uuid = id_string 1 in
  let mid = obs_id 1 in
  Alcotest.(check (option hit_t))
    "id + an unrelated property" (Some (Features.Member mid))
    (Features.hit (`Assoc [("id", `String uuid); ("count", `Int 1)]));
  Alcotest.(check (option hit_t))
    "id + role member" (Some (Features.Member mid))
    (Features.hit (`Assoc [("id", `String uuid); ("role", `String "member")]))

let hit_none () =
  Alcotest.(check (option hit_t))
    "an unparsable id" None
    (Features.hit (`Assoc [("id", `String "nope")]));
  Alcotest.(check (option hit_t))
    "id not a string" None
    (Features.hit (`Assoc [("id", `Int 3)]));
  Alcotest.(check (option hit_t)) "a bare list" None (Features.hit (`List []));
  Alcotest.(check (option hit_t))
    "an empty object" None
    (Features.hit (`Assoc []))

let hit_round_trips_through_place_points_and_selection () =
  let places = Features.places ~keep:always_true three_spots in
  let check_features json =
    let open Yojson.Safe.Util in
    json
    |> member "features"
    |> to_list
    |> List.iter (fun feature ->
        let props = feature |> member "properties" in
        let id = props |> member "id" |> to_string in
        match Features.hit props with
        | Some (Features.Member got) ->
            Alcotest.(check string)
              "round trip id" id
              (Ids.Observation_id.to_string got)
        | Some (Features.Group _) ->
            Alcotest.fail "a place or member feature decoded as Group"
        | None ->
            Alcotest.failf "hit gave None on %s" (Yojson.Safe.to_string props))
  in
  check_features (Features.place_points places);
  check_features (Features.selection (Some (List.hd places)))

let places_literal_keys () =
  Alcotest.(check string) "Features.count_key" "count" Features.count_key;
  Alcotest.(check string)
    "Features.identified_key" "identified" Features.identified_key;
  Alcotest.(check string) "Features.role_key" "role" Features.role_key;
  Alcotest.(check string) "Features.west_key" "west" Features.west_key;
  Alcotest.(check string) "Features.south_key" "south" Features.south_key;
  Alcotest.(check string) "Features.east_key" "east" Features.east_key;
  Alcotest.(check string) "Features.north_key" "north" Features.north_key

(* ---------- Style.with_overlays ---------- *)

let liberty_text =
  In_channel.with_open_bin "../../web/map/liberty.json" In_channel.input_all

let liberty = Yojson.Safe.from_string liberty_text

let colours : Style.colours =
  {
    point = "POINT";
    point_border = "POINT_BORDER";
    selected = "SELECTED";
    selected_halo = "SELECTED_HALO";
    to_identify = "TO_IDENTIFY";
    accuracy_fill = "ACCURACY_FILL";
    accuracy_line = "ACCURACY_LINE";
    origin = "ORIGIN";
  }

let with_overlays_ok base =
  match Style.with_overlays colours base with
  | Ok result -> result
  | Error e -> Alcotest.failf "with_overlays: %s" (Style.error_to_string e)

let liberty_fixture_sanity () =
  let open Yojson.Safe.Util in
  Alcotest.(check int)
    "style version is 8" 8
    (liberty |> member "version" |> to_int);
  Alcotest.(check bool)
    "sources contains openmaptiles" true
    (liberty |> member "sources" |> to_assoc |> List.mem_assoc "openmaptiles");
  Alcotest.(check bool)
    "layers is non-empty" true
    (liberty |> member "layers" |> to_list <> []);
  Alcotest.(check bool)
    "has glyphs" true
    (liberty |> member "glyphs" |> to_string_option <> None);
  Alcotest.(check bool)
    "has sprite" true
    (liberty |> member "sprite" |> to_string_option <> None)

let layers_appended_after_the_base () =
  let result = with_overlays_ok liberty in
  let open Yojson.Safe.Util in
  let base_layers = liberty |> member "layers" |> to_list in
  let layers = result |> member "layers" |> to_list in
  let n = List.length base_layers in
  Alcotest.(check int) "12 layers appended" (n + 12) (List.length layers);
  Alcotest.(check (list Testable.yojson))
    "the base layers are unchanged and in order" base_layers
    (List.filteri (fun i _ -> i < n) layers);
  let overlay_ids =
    List.filteri (fun i _ -> i >= n) layers
    |> List.map (fun l -> l |> member "id" |> to_string)
  in
  Alcotest.(check (list string))
    "overlay layer ids, in order, origin_layer right before focus_layer"
    [
      Style.accuracy_fill_layer;
      Style.accuracy_line_layer;
      Style.points_layer;
      Style.groups_layer;
      Style.groups_count_layer;
      Style.places_layer;
      Style.members_layer;
      Style.selection_halo_layer;
      Style.selection_place_layer;
      Style.selection_members_layer;
      Style.origin_layer;
      Style.focus_layer;
    ]
    overlay_ids

let source_by_id result id =
  let open Yojson.Safe.Util in
  result |> member "sources" |> to_assoc |> List.assoc id

(* [minzoom]/[maxzoom]/[clusterMaxZoom] are JSON numbers that the
   implementation may write as [`Int] or [`Float] (both spell "15" in the
   style JSON; [clusterMaxZoom] is computed as [detail_zoom -. 1.], a float);
   [number_field] reads either representation, and [check_layer_shape] checks
   a zoom field numerically while comparing the rest of the layer with
   [Yojson.Safe.equal]. *)
let number_field (j : Yojson.Safe.t) key =
  match j with
  | `Assoc fields ->
      Option.map Yojson.Safe.Util.to_number (List.assoc_opt key fields)
  | _ -> None

let strip_field key (j : Yojson.Safe.t) =
  match j with
  | `Assoc fields ->
      `Assoc (List.filter (fun (k, _) -> not (String.equal k key)) fields)
  | other -> other

let sources_appended_after_the_base () =
  let result = with_overlays_ok liberty in
  let open Yojson.Safe.Util in
  let base_sources = liberty |> member "sources" |> to_assoc in
  let sources = result |> member "sources" |> to_assoc in
  let n = List.length base_sources in
  Alcotest.(check (list (pair string Testable.yojson)))
    "the base sources are unchanged and in order" base_sources
    (List.filteri (fun i _ -> i < n) sources);
  let overlay = List.filteri (fun i _ -> i >= n) sources in
  Alcotest.(check (list string))
    "overlay source ids, in order, origin_source right before focus_source"
    [
      Style.observations_source;
      Style.accuracy_source;
      Style.places_source;
      Style.members_source;
      Style.selection_source;
      Style.origin_source;
      Style.focus_source;
    ]
    (List.map fst overlay);
  List.iter
    (fun id ->
      Alcotest.(check Testable.yojson)
        (Printf.sprintf
           "%s is a plain geojson source holding Features.empty, no cluster" id)
        (`Assoc [("type", `String "geojson"); ("data", Features.empty)])
        (List.assoc id overlay))
    [
      Style.observations_source;
      Style.accuracy_source;
      Style.members_source;
      Style.selection_source;
      Style.origin_source;
      Style.focus_source;
    ]

let places_source_shape () =
  let result = with_overlays_ok liberty in
  let source = source_by_id result Style.places_source in
  (match number_field source "clusterMaxZoom" with
  | Some v -> Alcotest.(check (float 1e-9)) "clusterMaxZoom is 14" 14. v
  | None -> Alcotest.fail "the places source has no clusterMaxZoom");
  Alcotest.(check Testable.yojson)
    "the places source clusters, with the summed/min/max cluster properties \
     (clusterMaxZoom checked separately above)"
    (`Assoc
       [
         ("type", `String "geojson");
         ("data", Features.empty);
         ("cluster", `Bool true);
         ("clusterRadius", `Int 40);
         ( "clusterProperties",
           `Assoc
             [
               ( "count",
                 `List [`String "+"; `List [`String "get"; `String "count"]] );
               ( "identified",
                 `List
                   [`String "+"; `List [`String "get"; `String "identified"]] );
               ( "west",
                 `List [`String "min"; `List [`String "get"; `String "west"]] );
               ( "south",
                 `List [`String "min"; `List [`String "get"; `String "south"]]
               );
               ( "east",
                 `List [`String "max"; `List [`String "get"; `String "east"]] );
               ( "north",
                 `List [`String "max"; `List [`String "get"; `String "north"]]
               );
             ] );
       ])
    (strip_field "clusterMaxZoom" source)

let places_source_and_layer_share_the_literal () =
  Alcotest.(check string)
    "places_source and places_layer share \"herbier-places\" (sources and \
     layers are separate namespaces)"
    Style.places_source Style.places_layer;
  (* The shared id is not a Duplicate_id. *)
  ignore (with_overlays_ok liberty)

let origin_source_and_layer_share_the_literal () =
  Alcotest.(check string)
    "origin_source and origin_layer share \"herbier-origin\" (sources and \
     layers are separate namespaces)"
    Style.origin_source Style.origin_layer;
  (* The shared id is not a Duplicate_id. *)
  ignore (with_overlays_ok liberty)

let other_top_level_keys_unchanged () =
  let result = with_overlays_ok liberty in
  let open Yojson.Safe.Util in
  let others j =
    List.filter
      (fun (k, _) -> not (List.mem k ["sources"; "layers"]))
      (to_assoc j)
  in
  Alcotest.(check (list string))
    "the base has version, glyphs and sprite among its other keys" []
    (List.filter
       (fun k -> not (List.mem_assoc k (others liberty)))
       ["version"; "glyphs"; "sprite"]);
  Alcotest.(check (list (pair string Testable.yojson)))
    "every top-level key other than sources and layers is unchanged, in order"
    (others liberty) (others result)

let layer_by_id result id =
  let open Yojson.Safe.Util in
  result
  |> member "layers"
  |> to_list
  |> List.find (fun l -> String.equal (l |> member "id" |> to_string) id)

let colours_applied_to_the_overlay_layers () =
  let result = with_overlays_ok liberty in
  let open Yojson.Safe.Util in
  let points = layer_by_id result Style.points_layer in
  let points_paint = points |> member "paint" in
  Alcotest.(check string)
    "the points layer is a circle layer" "circle"
    (points |> member "type" |> to_string);
  Alcotest.(check Testable.yojson)
    "circle-color is the kind match expression"
    (`List
       [
         `String "match";
         `List [`String "get"; `String "kind"];
         `String "to_identify";
         `String colours.to_identify;
         `String colours.point;
       ])
    (points_paint |> member "circle-color");
  Alcotest.(check string)
    "circle-stroke-color is point_border" colours.point_border
    (points_paint |> member "circle-stroke-color" |> to_string);
  Alcotest.(check int)
    "circle-radius is 6" 6
    (points_paint |> member "circle-radius" |> to_int);
  Alcotest.(check int)
    "circle-stroke-width is 3" 3
    (points_paint |> member "circle-stroke-width" |> to_int);
  Alcotest.(check string)
    "the points layer reads the observations source" Style.observations_source
    (points |> member "source" |> to_string);
  let fill = layer_by_id result Style.accuracy_fill_layer in
  Alcotest.(check string)
    "the accuracy fill layer is a fill layer" "fill"
    (fill |> member "type" |> to_string);
  Alcotest.(check string)
    "fill-color is accuracy_fill" colours.accuracy_fill
    (fill |> member "paint" |> member "fill-color" |> to_string);
  Alcotest.(check string)
    "the fill layer reads the accuracy source" Style.accuracy_source
    (fill |> member "source" |> to_string);
  let line = layer_by_id result Style.accuracy_line_layer in
  Alcotest.(check string)
    "the accuracy line layer is a line layer" "line"
    (line |> member "type" |> to_string);
  Alcotest.(check string)
    "line-color is accuracy_line" colours.accuracy_line
    (line |> member "paint" |> member "line-color" |> to_string);
  Alcotest.(check int)
    "line-width is 1" 1
    (line |> member "paint" |> member "line-width" |> to_int);
  Alcotest.(check string)
    "the line layer reads the accuracy source" Style.accuracy_source
    (line |> member "source" |> to_string)

let focus_paint =
  `Assoc
    [
      ("circle-radius", `Int 7);
      ("circle-color", `String colours.selected);
      ("circle-stroke-width", `Int 3);
      ("circle-stroke-color", `String colours.point_border);
    ]

let origin_paint =
  `Assoc
    [
      ("circle-radius", `Int 6);
      ("circle-color", `String colours.origin);
      ("circle-stroke-width", `Int 3);
      ("circle-stroke-color", `String colours.point_border);
      ("circle-opacity", `Float 0.7);
      ("circle-stroke-opacity", `Float 0.7);
    ]

let overlay_paints_are_exact () =
  let result = with_overlays_ok liberty in
  let open Yojson.Safe.Util in
  let paint id = layer_by_id result id |> member "paint" in
  Alcotest.(check Testable.yojson)
    "the whole points paint"
    (`Assoc
       [
         ("circle-radius", `Int 6);
         ("circle-stroke-width", `Int 3);
         ("circle-stroke-color", `String colours.point_border);
         ( "circle-color",
           `List
             [
               `String "match";
               `List [`String "get"; `String "kind"];
               `String "to_identify";
               `String colours.to_identify;
               `String colours.point;
             ] );
       ])
    (paint Style.points_layer);
  Alcotest.(check Testable.yojson)
    "the whole accuracy fill paint"
    (`Assoc [("fill-color", `String colours.accuracy_fill)])
    (paint Style.accuracy_fill_layer);
  Alcotest.(check Testable.yojson)
    "the whole accuracy line paint"
    (`Assoc
       [("line-color", `String colours.accuracy_line); ("line-width", `Int 1)])
    (paint Style.accuracy_line_layer);
  Alcotest.(check Testable.yojson)
    "the whole origin paint" origin_paint (paint Style.origin_layer);
  Alcotest.(check Testable.yojson)
    "the whole focus paint" focus_paint (paint Style.focus_layer)

let check_layer_shape ~msg ~zoom_field ~zoom_value expected_without_zoom actual
    =
  (match number_field actual zoom_field with
  | Some v ->
      Alcotest.(check (float 1e-9)) (msg ^ ": " ^ zoom_field) zoom_value v
  | None -> Alcotest.failf "%s: no %s" msg zoom_field);
  Alcotest.(check Testable.yojson)
    (msg ^ ": shape apart from " ^ zoom_field)
    expected_without_zoom
    (strip_field zoom_field actual)

let identified_case =
  `List
    [
      `String "case";
      `List [`String "=="; `List [`String "get"; `String "identified"]; `Int 0];
      `String colours.to_identify;
      `String colours.point;
    ]

let groups_layer_shape () =
  let result = with_overlays_ok liberty in
  check_layer_shape ~msg:"groups_layer" ~zoom_field:"maxzoom"
    ~zoom_value:Style.detail_zoom
    (`Assoc
       [
         ("id", `String Style.groups_layer);
         ("type", `String "circle");
         ("source", `String Style.places_source);
         ("filter", `List [`String "has"; `String "point_count"]);
         ( "paint",
           `Assoc
             [
               ("circle-radius", `Int 9);
               ("circle-stroke-width", `Int 3);
               ("circle-stroke-color", `String colours.point_border);
               ("circle-color", identified_case);
             ] );
       ])
    (layer_by_id result Style.groups_layer)

let groups_count_layer_shape () =
  let result = with_overlays_ok liberty in
  check_layer_shape ~msg:"groups_count_layer" ~zoom_field:"maxzoom"
    ~zoom_value:Style.detail_zoom
    (`Assoc
       [
         ("id", `String Style.groups_count_layer);
         ("type", `String "symbol");
         ("source", `String Style.places_source);
         ("filter", `List [`String "has"; `String "point_count"]);
         ( "layout",
           `Assoc
             [
               ( "text-field",
                 `List
                   [`String "to-string"; `List [`String "get"; `String "count"]]
               );
               ("text-font", `List [`String "Noto Sans Bold"]);
               ("text-size", `Int 11);
               ("text-allow-overlap", `Bool true);
             ] );
         ("paint", `Assoc [("text-color", `String colours.point_border)]);
       ])
    (layer_by_id result Style.groups_count_layer)

let places_layer_shape () =
  let result = with_overlays_ok liberty in
  check_layer_shape ~msg:"places_layer" ~zoom_field:"maxzoom"
    ~zoom_value:Style.detail_zoom
    (`Assoc
       [
         ("id", `String Style.places_layer);
         ("type", `String "circle");
         ("source", `String Style.places_source);
         ( "filter",
           `List [`String "!"; `List [`String "has"; `String "point_count"]] );
         ( "paint",
           `Assoc
             [
               ("circle-radius", `Int 6);
               ("circle-stroke-width", `Int 3);
               ("circle-stroke-color", `String colours.point_border);
               ("circle-color", identified_case);
             ] );
       ])
    (layer_by_id result Style.places_layer)

let members_layer_shape () =
  let result = with_overlays_ok liberty in
  check_layer_shape ~msg:"members_layer" ~zoom_field:"minzoom"
    ~zoom_value:Style.detail_zoom
    (`Assoc
       [
         ("id", `String Style.members_layer);
         ("type", `String "circle");
         ("source", `String Style.members_source);
         ( "paint",
           `Assoc
             [
               ("circle-radius", `Int 6);
               ("circle-stroke-width", `Int 3);
               ("circle-stroke-color", `String colours.point_border);
               ( "circle-color",
                 `List
                   [
                     `String "match";
                     `List [`String "get"; `String "kind"];
                     `String "to_identify";
                     `String colours.to_identify;
                     `String colours.point;
                   ] );
             ] );
       ])
    (layer_by_id result Style.members_layer)

let selection_halo_layer_shape () =
  let result = with_overlays_ok liberty in
  check_layer_shape ~msg:"selection_halo_layer" ~zoom_field:"maxzoom"
    ~zoom_value:Style.detail_zoom
    (`Assoc
       [
         ("id", `String Style.selection_halo_layer);
         ("type", `String "circle");
         ("source", `String Style.selection_source);
         ( "filter",
           `List
             [
               `String "==";
               `List [`String "get"; `String "role"];
               `String "place";
             ] );
         ( "paint",
           `Assoc
             [
               ("circle-radius", `Int 28);
               ("circle-color", `String colours.selected_halo);
               ("circle-stroke-width", `Int 2);
               ("circle-stroke-color", `String colours.selected);
             ] );
       ])
    (layer_by_id result Style.selection_halo_layer)

let selection_place_layer_shape () =
  let result = with_overlays_ok liberty in
  check_layer_shape ~msg:"selection_place_layer" ~zoom_field:"maxzoom"
    ~zoom_value:Style.detail_zoom
    (`Assoc
       [
         ("id", `String Style.selection_place_layer);
         ("type", `String "circle");
         ("source", `String Style.selection_source);
         ( "filter",
           `List
             [
               `String "==";
               `List [`String "get"; `String "role"];
               `String "place";
             ] );
         ( "paint",
           `Assoc
             [
               ("circle-radius", `Int 7);
               ("circle-stroke-width", `Int 3);
               ("circle-stroke-color", `String colours.point_border);
               ("circle-color", `String colours.selected);
             ] );
       ])
    (layer_by_id result Style.selection_place_layer)

let selection_members_layer_shape () =
  let result = with_overlays_ok liberty in
  check_layer_shape ~msg:"selection_members_layer" ~zoom_field:"minzoom"
    ~zoom_value:Style.detail_zoom
    (`Assoc
       [
         ("id", `String Style.selection_members_layer);
         ("type", `String "circle");
         ("source", `String Style.selection_source);
         ( "filter",
           `List
             [
               `String "==";
               `List [`String "get"; `String "role"];
               `String "member";
             ] );
         ( "paint",
           `Assoc
             [
               ("circle-radius", `Int 7);
               ("circle-stroke-width", `Int 3);
               ("circle-stroke-color", `String colours.point_border);
               ("circle-color", `String colours.selected);
             ] );
       ])
    (layer_by_id result Style.selection_members_layer)

let focus_layer_shape () =
  let result = with_overlays_ok liberty in
  Alcotest.(check Testable.yojson)
    "focus_layer: a circle layer on focus_source, paint only, no \
     minzoom/maxzoom/filter"
    (`Assoc
       [
         ("id", `String Style.focus_layer);
         ("type", `String "circle");
         ("source", `String Style.focus_source);
         ("paint", focus_paint);
       ])
    (layer_by_id result Style.focus_layer)

let origin_layer_shape () =
  let result = with_overlays_ok liberty in
  Alcotest.(check Testable.yojson)
    "origin_layer: a circle layer on origin_source, paint only, no \
     minzoom/maxzoom/filter (shown at every zoom)"
    (`Assoc
       [
         ("id", `String Style.origin_layer);
         ("type", `String "circle");
         ("source", `String Style.origin_source);
         ("paint", origin_paint);
       ])
    (layer_by_id result Style.origin_layer)

let base_text_fonts () =
  let open Yojson.Safe.Util in
  liberty
  |> member "layers"
  |> to_list
  |> List.concat_map (fun l ->
      (* [member] raises on a non-object receiver, and a layer without
         [layout] gives [`Null] for it, not an empty object. *)
      match member "layout" l with
      | `Assoc _ as layout -> (
          match member "text-font" layout with
          | `List fonts -> List.filter_map to_string_option fonts
          | _ -> [])
      | _ -> [])

let new_text_fonts_exist_on_the_server () =
  let result = with_overlays_ok liberty in
  let open Yojson.Safe.Util in
  let fonts =
    match
      layer_by_id result Style.groups_count_layer
      |> member "layout"
      |> member "text-font"
    with
    | `List l -> List.filter_map to_string_option l
    | _ -> Alcotest.fail "groups_count_layer has no text-font in its layout"
  in
  let available = base_text_fonts () in
  List.iter
    (fun f ->
      Alcotest.(check bool)
        (Printf.sprintf "%S is used by some liberty layer's own text-font" f)
        true (List.mem f available))
    fonts

let detail_zoom_consistency () =
  Alcotest.(check (float 0.)) "Style.detail_zoom is 15." 15. Style.detail_zoom;
  let result = with_overlays_ok liberty in
  List.iter
    (fun id ->
      match number_field (layer_by_id result id) "maxzoom" with
      | Some v ->
          Alcotest.(check (float 1e-9))
            (Printf.sprintf "%s maxzoom = detail_zoom" id)
            Style.detail_zoom v
      | None -> Alcotest.failf "%s has no maxzoom" id)
    [
      Style.groups_layer;
      Style.places_layer;
      Style.selection_halo_layer;
      Style.selection_place_layer;
    ];
  List.iter
    (fun id ->
      match number_field (layer_by_id result id) "minzoom" with
      | Some v ->
          Alcotest.(check (float 1e-9))
            (Printf.sprintf "%s minzoom = detail_zoom" id)
            Style.detail_zoom v
      | None -> Alcotest.failf "%s has no minzoom" id)
    [Style.members_layer; Style.selection_members_layer];
  match
    number_field (source_by_id result Style.places_source) "clusterMaxZoom"
  with
  | Some v ->
      Alcotest.(check (float 1e-9))
        "the places source's clusterMaxZoom is detail_zoom - 1"
        (Style.detail_zoom -. 1.) v
  | None -> Alcotest.fail "the places source has no clusterMaxZoom"

let kind_matches_the_style () =
  Alcotest.(check string) "Features.kind_key" "kind" Features.kind_key;
  Alcotest.(check string)
    "To_identify" "to_identify"
    (Features.kind_to_string Features.To_identify);
  Alcotest.(check string)
    "Identified" "identified"
    (Features.kind_to_string Features.Identified)

let with_overlays_errors () =
  let check msg expected input =
    Alcotest.(check (result Testable.yojson style_error))
      msg (Error expected)
      (Style.with_overlays colours input)
  in
  check "a null root is not a style" (Style.Not_a_style "root") `Null;
  check "an empty-list root is not a style" (Style.Not_a_style "root")
    (`List []);
  check "an object without layers" (Style.Not_a_style "layers")
    (`Assoc [("sources", `Assoc [])]);
  check "layers not a list" (Style.Not_a_style "layers")
    (`Assoc [("sources", `Assoc []); ("layers", `String "nope")]);
  check "an object without sources" (Style.Not_a_style "sources")
    (`Assoc [("layers", `List [])]);
  check "sources not an object" (Style.Not_a_style "sources")
    (`Assoc [("sources", `List []); ("layers", `List [])])

let with_overlays_duplicate_ids () =
  let expect_layer_dup id =
    Alcotest.(check (result Testable.yojson style_error))
      (Printf.sprintf "a layer named %s already present" id)
      (Error (Style.Duplicate_id id))
      (Style.with_overlays colours
         (`Assoc
            [
              ("sources", `Assoc []);
              ("layers", `List [`Assoc [("id", `String id)]]);
            ]))
  in
  let expect_source_dup id =
    Alcotest.(check (result Testable.yojson style_error))
      (Printf.sprintf "a source named %s already present" id)
      (Error (Style.Duplicate_id id))
      (Style.with_overlays colours
         (`Assoc [("sources", `Assoc [(id, `Assoc [])]); ("layers", `List [])]))
  in
  (* Every new layer id, including [places_layer] (= "herbier-places"), given
     only as a base *layer*, with no matching base source. *)
  List.iter expect_layer_dup
    [
      Style.accuracy_fill_layer;
      Style.accuracy_line_layer;
      Style.points_layer;
      Style.groups_layer;
      Style.groups_count_layer;
      Style.places_layer;
      Style.members_layer;
      Style.selection_halo_layer;
      Style.selection_place_layer;
      Style.selection_members_layer;
      Style.origin_layer;
      Style.focus_layer;
    ];
  (* Every new source id, including [places_source] (= "herbier-places"),
     [origin_source] (= "herbier-origin") and [focus_source] (=
     "herbier-focus"), given only as a base *source*, with no matching base
     layer. *)
  List.iter expect_source_dup
    [
      Style.observations_source;
      Style.accuracy_source;
      Style.places_source;
      Style.members_source;
      Style.selection_source;
      Style.origin_source;
      Style.focus_source;
    ];
  let once = with_overlays_ok liberty in
  match Style.with_overlays colours once with
  | Error (Style.Duplicate_id _) -> ()
  | Error (Style.Not_a_style key) ->
      Alcotest.failf
        "re-applying with_overlays to its own output gave Not_a_style %s" key
  | Ok _ ->
      Alcotest.fail "re-applying with_overlays to its own output should fail"

let literal_ids () =
  Alcotest.(check string) "Style.path" "map/liberty.json" Style.path;
  Alcotest.(check string)
    "Style.observations_source" "herbier-observations" Style.observations_source;
  Alcotest.(check string)
    "Style.accuracy_source" "herbier-accuracy" Style.accuracy_source;
  Alcotest.(check string)
    "Style.points_layer" "herbier-points" Style.points_layer;
  Alcotest.(check string)
    "Style.accuracy_fill_layer" "herbier-accuracy-fill"
    Style.accuracy_fill_layer;
  Alcotest.(check string)
    "Style.accuracy_line_layer" "herbier-accuracy-line"
    Style.accuracy_line_layer;
  Alcotest.(check string)
    "Style.places_source" "herbier-places" Style.places_source;
  Alcotest.(check string)
    "Style.members_source" "herbier-members" Style.members_source;
  Alcotest.(check string)
    "Style.selection_source" "herbier-selection" Style.selection_source;
  Alcotest.(check string)
    "Style.groups_layer" "herbier-groups" Style.groups_layer;
  Alcotest.(check string)
    "Style.groups_count_layer" "herbier-groups-count" Style.groups_count_layer;
  Alcotest.(check string)
    "Style.places_layer" "herbier-places" Style.places_layer;
  Alcotest.(check string)
    "Style.members_layer" "herbier-members" Style.members_layer;
  Alcotest.(check string)
    "Style.selection_halo_layer" "herbier-selection-halo"
    Style.selection_halo_layer;
  Alcotest.(check string)
    "Style.selection_place_layer" "herbier-selection-place"
    Style.selection_place_layer;
  Alcotest.(check string)
    "Style.selection_members_layer" "herbier-selection-members"
    Style.selection_members_layer;
  Alcotest.(check string)
    "Style.focus_source" "herbier-focus" Style.focus_source;
  Alcotest.(check string) "Style.focus_layer" "herbier-focus" Style.focus_layer;
  Alcotest.(check string)
    "Style.origin_source" "herbier-origin" Style.origin_source;
  Alcotest.(check string)
    "Style.origin_layer" "herbier-origin" Style.origin_layer

let error_to_string_covers_both_constructors () =
  Alcotest.(check bool)
    "Not_a_style names the key" true
    (Text.contains ~sub:"layers"
       (Style.error_to_string (Style.Not_a_style "layers")));
  Alcotest.(check bool)
    "Duplicate_id names the id" true
    (Text.contains ~sub:"herbier-points"
       (Style.error_to_string (Style.Duplicate_id "herbier-points")))

let tests =
  [
    ( "Features.observations [] equals Features.empty",
      `Quick,
      observations_empty_is_the_empty_collection );
    ( "Features.observations: an identified observation gives kind identified",
      `Quick,
      observations_identified );
    ( "Features.observations: plant_id = None gives kind to_identify",
      `Quick,
      observations_to_identify );
    ( "Features.observations drops unplaceable observations",
      `Quick,
      observations_unplaceable_absent );
    ( "Features.observations orders features ascending by at",
      `Quick,
      observations_order_ascending_at );
    ( "Features.observations breaks an equal at by ascending id",
      `Quick,
      observations_order_tie_by_id );
    ( "Features.observations never serialises nan or infinity",
      `Quick,
      observations_round_trips_through_json_text );
    ( "Features.bounds is None for [] and all-unplaceable",
      `Quick,
      bounds_none_for_empty_or_unplaceable );
    ("Features.bounds of one point collapses to it", `Quick, bounds_one_point);
    ( "Features.bounds takes the min/max of placeable points only",
      `Quick,
      bounds_three_points_ignore_unplaceable );
    ( "Features.circle of 64 steps is a 65-vertex closed ring",
      `Quick,
      circle_shape );
    ( "Features.circle: every vertex is radius_m from the centre",
      `Quick,
      circle_vertices_are_at_radius );
    ( "Features.circle: vertex 0 is north, vertex 16 of 64 is east",
      `Quick,
      circle_bearings );
    ( "Features.circle is empty for an invalid radius, steps or centre",
      `Quick,
      circle_empty_on_invalid_input );
    ( "Features.circle with 3 steps is a closed 4-position ring",
      `Quick,
      circle_three_steps );
    ( "Features.circle stays finite close to the pole",
      `Quick,
      circle_at_the_pole );
    ( "Features.circle_bounds equals the min/max of circle's own ring",
      `Quick,
      circle_bounds_matches_circle_ring_extremes );
    ( "Features.circle_bounds: the lat/lon half-spans approximate the \
       spherical-earth formula",
      `Quick,
      circle_bounds_degree_approximation );
    ( "Features.circle_bounds at the equator is symmetric",
      `Quick,
      circle_bounds_symmetric_at_equator );
    ( "Features.circle_bounds: the lon half-span widens with latitude",
      `Quick,
      circle_bounds_lon_span_widens_with_latitude );
    ( "Features.circle_bounds always contains its centre",
      `Quick,
      circle_bounds_contains_the_centre );
    ( "Features.circle_bounds stays contiguous across the antimeridian",
      `Quick,
      circle_bounds_contiguous_across_the_antimeridian );
    ( "Features.circle_bounds is None for an invalid radius or centre",
      `Quick,
      circle_bounds_none_on_invalid_input );
    ( "Features.accuracy_bounds with a positive finite accuracy delegates to \
       circle_bounds",
      `Quick,
      accuracy_bounds_matches_circle_bounds );
    ( "Features.accuracy_bounds collapses to the point for \
       no/zero/negative/non-finite accuracy",
      `Quick,
      accuracy_bounds_degenerate_box );
    ( "Features.accuracy_bounds is None for a non-finite position",
      `Quick,
      accuracy_bounds_none_on_nonfinite_position );
    ("Features.focus None is Features.empty", `Quick, focus_none_is_empty);
    ( "Features.focus Some: a lone point feature with no properties, lon \
       before lat",
      `Quick,
      focus_some_is_a_lone_point_feature_with_no_properties );
    ( "Features.focus is empty for a non-finite coordinate",
      `Quick,
      focus_nonfinite_coordinate_is_empty );
    ( "Features' kind strings are the ones Style matches",
      `Quick,
      kind_matches_the_style );
    ( "Features.places: key, shown and cluster.members with keep always true",
      `Quick,
      places_everything );
    ( "Features.places: dropping a whole cluster removes its place only",
      `Quick,
      places_whole_cluster_dropped );
    ( "Features.places: dropping the earliest member keeps the place and its key",
      `Quick,
      places_earliest_member_dropped );
    ( "Features.places: keep sees the member's own cluster",
      `Quick,
      places_keep_sees_the_cluster );
    ( "Features.places: unplaceable observations and [] give []",
      `Quick,
      places_unplaceable_and_empty );
    ( "Features.find locates a place by any cluster member, shown or not",
      `Quick,
      find_by_any_member );
    ( "Features.find is None for an unknown or unplaceable id",
      `Quick,
      find_absent );
    ( "Features.place_points: one feature per place, in order, with the \
       mixed/all-unidentified counts",
      `Quick,
      place_points_order_and_counts );
    ( "Features.place_points: properties and geometry are exact",
      `Quick,
      place_points_properties_are_exact );
    ( "Features.place_points [] is Features.empty",
      `Quick,
      place_points_empty_for_no_places );
    ( "Features.selection None is Features.empty",
      `Quick,
      selection_none_is_empty );
    ( "Features.selection Some: place feature then members in compare_obs \
       order, exact properties",
      `Quick,
      selection_some );
    ("Features.hit decodes a cluster feature into Group", `Quick, hit_group);
    ( "Features.hit: a cluster feature missing or with a non-finite bound is \
       None",
      `Quick,
      hit_group_missing_or_nonfinite_bound );
    ("Features.hit decodes an id into Member", `Quick, hit_member);
    ("Features.hit is None for anything else", `Quick, hit_none);
    ( "Features.hit round-trips every place_points and selection feature's id",
      `Quick,
      hit_round_trips_through_place_points_and_selection );
    ( "Features.place_points: distinct bounds, centroid of the whole cluster",
      `Quick,
      place_points_bounds_and_centroid );
    ( "Features.place_points and selection count and list shown, not members",
      `Quick,
      place_points_and_selection_follow_shown );
    ( "Features' place-related keys are the wire literals",
      `Quick,
      places_literal_keys );
    ( "the recorded liberty.json has the expected shape",
      `Quick,
      liberty_fixture_sanity );
    ( "Style.with_overlays appends 12 layers after the base",
      `Quick,
      layers_appended_after_the_base );
    ( "Style.with_overlays appends 7 sources after the base (6 plain, 1 \
       clustered)",
      `Quick,
      sources_appended_after_the_base );
    ( "Style.with_overlays: the places source clusters",
      `Quick,
      places_source_shape );
    ( "places_source and places_layer share \"herbier-places\" without colliding",
      `Quick,
      places_source_and_layer_share_the_literal );
    ( "origin_source and origin_layer share \"herbier-origin\" without colliding",
      `Quick,
      origin_source_and_layer_share_the_literal );
    ( "Style.with_overlays leaves other top-level keys unchanged",
      `Quick,
      other_top_level_keys_unchanged );
    ( "Style.with_overlays applies colours to the overlay layers",
      `Quick,
      colours_applied_to_the_overlay_layers );
    ( "Style.with_overlays: the overlay paints are exactly the expected ones",
      `Quick,
      overlay_paints_are_exact );
    ( "Style.with_overlays: groups_layer's shape is exact",
      `Quick,
      groups_layer_shape );
    ( "Style.with_overlays: groups_count_layer's shape is exact",
      `Quick,
      groups_count_layer_shape );
    ( "Style.with_overlays: places_layer's shape is exact",
      `Quick,
      places_layer_shape );
    ( "Style.with_overlays: members_layer's shape is exact",
      `Quick,
      members_layer_shape );
    ( "Style.with_overlays: selection_halo_layer's shape is exact",
      `Quick,
      selection_halo_layer_shape );
    ( "Style.with_overlays: selection_place_layer's shape is exact",
      `Quick,
      selection_place_layer_shape );
    ( "Style.with_overlays: selection_members_layer's shape is exact",
      `Quick,
      selection_members_layer_shape );
    ( "Style.with_overlays: focus_layer's shape is exact",
      `Quick,
      focus_layer_shape );
    ( "Style.with_overlays: origin_layer's shape is exact (5b's origin ghost)",
      `Quick,
      origin_layer_shape );
    ( "the new layers' text-font stacks exist among liberty's own layers",
      `Quick,
      new_text_fonts_exist_on_the_server );
    ( "Style.detail_zoom is 15 and matches the layers' min/maxzoom and the \
       places source's clusterMaxZoom",
      `Quick,
      detail_zoom_consistency );
    ( "Style.with_overlays rejects a base that is not a style",
      `Quick,
      with_overlays_errors );
    ( "Style.with_overlays rejects a duplicate source or layer id",
      `Quick,
      with_overlays_duplicate_ids );
    ("Style's path and overlay ids are the wire literals", `Quick, literal_ids);
    ( "Style.error_to_string covers both constructors",
      `Quick,
      error_to_string_covers_both_constructors );
  ]

let () = Alcotest.run "geo" [("features and style", tests)]
