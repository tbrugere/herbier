(* Hand-written point sets around an arbitrary reference point.
   Expected distances are closed forms (R·π/180, π·R) or were computed
   independently (Python haversine with R = 6 371 000 m) and are written as
   literals. Points moved along a meridian with [north_of] are exactly [m]
   metres away up to rounding, and the mean of their latitudes is the mean
   of their offsets, so expected centroids are computed from the inputs, not
   by the module under test. *)

module Places = Herbier_domain.Places
module Observation = Herbier_domain.Observation
module Ids = Herbier_domain.Ids

(* Inputs *)

let o : Places.point = {lat = 45.0; lon = 5.0}
let deg_of_m m = m /. Places.earth_radius_m *. 180. /. Float.pi

let north_of (p : Places.point) m : Places.point =
  {p with lat = p.lat +. deg_of_m m}

let east_on_equator m : Places.point = {lat = 0.; lon = deg_of_m m}
let base_time = 1_700_000_000.

let time s =
  match Ptime.of_float_s (base_time +. float_of_int s) with
  | Some t -> t
  | None -> Alcotest.failf "Ptime.of_float_s rejected offset %d" s

(* Zero-padded, so ids compare in the order of [n]. *)
let id_string n = Printf.sprintf "00000000-0000-4000-8000-%012d" n

let obs_id n =
  match Ids.Observation_id.of_string (id_string n) with
  | Some id -> id
  | None -> Alcotest.failf "Observation_id.of_string %S gave None" (id_string n)

(* [obs ~id ~at pos]: an observation with id number [id], taken [at] seconds
   after [base_time], at [pos]. *)
let obs ?label ?derived ?(deleted = false) ~id ~at pos : Observation.t =
  let at = time at in
  {
    id = obs_id id;
    plant_id = None;
    at;
    position =
      Option.map
        (fun (p : Places.point) ->
          {Observation.lat = p.lat; lon = p.lon; accuracy_m = None})
        pos;
    place_label = label;
    place_derived = derived;
    note = None;
    created_at = at;
    updated_at = at;
    deleted_at = (if deleted then Some at else None);
  }

let mean_lat (ps : Places.point list) =
  List.fold_left (fun acc (p : Places.point) -> acc +. p.lat) 0. ps
  /. float_of_int (List.length ps)

(* Testables *)

let pp_point f (p : Places.point) =
  Format.fprintf f "{lat = %.12g; lon = %.12g}" p.lat p.lon

let close_point (a : Places.point) (b : Places.point) =
  Float.abs (a.lat -. b.lat) <= 1e-9 && Float.abs (a.lon -. b.lon) <= 1e-9

let point = Alcotest.testable pp_point close_point

let pp_label f = function
  | Places.Named s -> Format.fprintf f "Named %S" s
  | Places.Derived s -> Format.fprintf f "Derived %S" s
  | Places.Coordinates p -> Format.fprintf f "Coordinates %a" pp_point p

let equal_label a b =
  match (a, b) with
  | Places.Named x, Places.Named y -> String.equal x y
  | Places.Derived x, Places.Derived y -> String.equal x y
  | Places.Coordinates p, Places.Coordinates q -> close_point p q
  | Places.Named _, (Places.Derived _ | Places.Coordinates _)
  | Places.Derived _, (Places.Named _ | Places.Coordinates _)
  | Places.Coordinates _, (Places.Named _ | Places.Derived _) ->
      false

let label = Alcotest.testable pp_label equal_label

let ids (os : Observation.t list) =
  List.map (fun (x : Observation.t) -> Ids.Observation_id.to_string x.id) os

let member_ids (cs : Places.cluster list) =
  List.map (fun (c : Places.cluster) -> ids c.members) cs

let centroids (cs : Places.cluster list) =
  List.map (fun (c : Places.cluster) -> c.centroid) cs

let check_members msg expected actual =
  Alcotest.(check (list (list string)))
    msg (List.map ids expected) (member_ids actual)

let metres eps = Alcotest.float eps

(* Distance, of_position, constants *)

let paris : Places.point = {lat = 48.8566; lon = 2.3522}
let london : Places.point = {lat = 51.5074; lon = -0.1278}
let cape_town : Places.point = {lat = -33.9; lon = 18.4}
let north_paris : Places.point = {lat = 48.9; lon = 2.35}
let one_degree_m = Places.earth_radius_m *. Float.pi /. 180.
let half_circumference_m = Float.pi *. Places.earth_radius_m

let distance_zero_for_equal_points () =
  Alcotest.(check (metres 0.)) "distance from o to o" 0. (Places.distance_m o o)

let distance_symmetric () =
  List.iter
    (fun ((a, b) : Places.point * Places.point) ->
      Alcotest.(check (metres 1e-9))
        (Format.asprintf "distance %a→%a equals the reverse" pp_point a pp_point
           b)
        (Places.distance_m b a) (Places.distance_m a b))
    [(o, north_of o 300.); (cape_town, north_paris); (paris, london)]

let distance_across_hemispheres () =
  Alcotest.(check (metres 1.))
    "Cape Town-like point to north of Paris, Python haversine" 9_343_342.587
    (Places.distance_m cape_town north_paris)

let distance_one_degree () =
  Alcotest.(check (metres 1e-6))
    "one degree of latitude from {0,0}" one_degree_m
    (Places.distance_m {lat = 0.; lon = 0.} {lat = 1.; lon = 0.});
  Alcotest.(check (metres 1e-6))
    "one degree of longitude on the equator" one_degree_m
    (Places.distance_m {lat = 0.; lon = 0.} {lat = 0.; lon = 1.})

let distance_antipodes () =
  let equator = Places.distance_m {lat = 0.; lon = 0.} {lat = 0.; lon = 180.} in
  let poles = Places.distance_m {lat = 90.; lon = 0.} {lat = -90.; lon = 0.} in
  Alcotest.(check bool)
    "equatorial antipodes are not nan" false (Float.is_nan equator);
  Alcotest.(check (metres 1e-6))
    "equatorial antipodes are π·R apart" half_circumference_m equator;
  Alcotest.(check bool) "poles are not nan" false (Float.is_nan poles);
  Alcotest.(check (metres 1e-6))
    "poles are π·R apart" half_circumference_m poles

let distance_antimeridian () =
  Alcotest.(check (metres 1e-6))
    "lon 180 and lon -180 at lat 10 are the same point" 0.
    (Places.distance_m {lat = 10.; lon = 180.} {lat = 10.; lon = -180.})

let distance_paris_london () =
  Alcotest.(check (metres 1.))
    "Paris to London, Python haversine" 343_556.060
    (Places.distance_m paris london)

let distance_north_500 () =
  Alcotest.(check (metres 1e-6))
    "north_of o 500 is 500 m from o" 500.
    (Places.distance_m o (north_of o 500.))

let distance_nan () =
  Alcotest.(check bool)
    "nan latitude gives nan" true
    (Float.is_nan (Places.distance_m {lat = Float.nan; lon = 0.} o));
  Alcotest.(check bool)
    "nan longitude as second argument gives nan" true
    (Float.is_nan (Places.distance_m o {lat = 0.; lon = Float.nan}))

let of_position_drops_accuracy () =
  Alcotest.(check point)
    "of_position keeps lat and lon" {lat = 1.; lon = 2.}
    (Places.of_position {Observation.lat = 1.; lon = 2.; accuracy_m = Some 12.})

let constants () =
  Alcotest.(check (metres 0.)) "radius_m" 500. Places.radius_m;
  Alcotest.(check (metres 0.)) "earth_radius_m" 6_371_000. Places.earth_radius_m

(* within *)

let within_cases () =
  let yes msg a b = Alcotest.(check bool) msg true (Places.within a b) in
  let no msg a b = Alcotest.(check bool) msg false (Places.within a b) in
  yes "a point is within itself" o o;
  yes "exactly 500 m north is within" o (north_of o 500.);
  yes "exactly 500 m east on the equator is within" {lat = 0.; lon = 0.}
    (east_on_equator 500.);
  yes "499.9 m north is within" o (north_of o 499.9);
  yes "500.0005 m north is within the 1 mm allowance" o (north_of o 500.0005);
  no "500.002 m north is beyond the 1 mm allowance" o (north_of o 500.002);
  no "500.01 m north is not within" o (north_of o 500.01);
  no "501 m north is not within" o (north_of o 501.);
  no "a nan latitude is not within" o {lat = Float.nan; lon = 5.};
  no "a nan first argument is not within" {lat = Float.nan; lon = 5.} o

(* cluster: the base set *)

let a1 = obs ~id:1 ~at:0 (Some o)
let a2 = obs ~id:2 ~at:1 (Some (north_of o 300.))
let b1 = obs ~id:3 ~at:2 (Some (north_of o 5000.))
let a3 = obs ~id:4 ~at:3 (Some (north_of o 100.))
let b2 = obs ~id:5 ~at:4 (Some (north_of o 5400.))
let c1 = obs ~id:6 ~at:5 (Some (north_of o 1200.))
let u1 = obs ~id:7 ~at:6 None
let d1 = obs ~id:8 ~at:7 ~deleted:true (Some o)
let n1 = obs ~id:9 ~at:8 (Some {lat = Float.nan; lon = 5.})
let i1 = obs ~id:10 ~at:9 (Some {lat = 45.; lon = Float.infinity})
let unplaceable = [u1; d1; n1; i1]

let position_point_live () =
  Alcotest.(check (option point))
    "a live observation with a position gives its point" (Some o)
    (Places.position_point a1)

let position_point_unplaceable () =
  Alcotest.(check (option point))
    "no position gives None" None (Places.position_point u1);
  Alcotest.(check (option point))
    "a deleted observation gives None" None (Places.position_point d1)

let position_point_nonfinite () =
  let neg_infinite_lon =
    obs ~id:11 ~at:10 (Some {lat = 45.; lon = Float.neg_infinity})
  in
  Alcotest.(check (option point))
    "a nan latitude gives None" None (Places.position_point n1);
  Alcotest.(check (option point))
    "an infinite longitude gives None" None (Places.position_point i1);
  Alcotest.(check (option point))
    "a negative infinite longitude gives None" None
    (Places.position_point neg_infinite_lon)

let base = [a1; a2; b1; a3; b2; c1; u1; d1; n1; i1]
let base_reversed = List.rev base
let base_shuffled = [c1; u1; a3; b1; n1; a1; i1; d1; b2; a2]

let centroid_a : Places.point =
  {lat = mean_lat [o; north_of o 300.; north_of o 100.]; lon = 5.}

let centroid_b : Places.point =
  {lat = mean_lat [north_of o 5000.; north_of o 5400.]; lon = 5.}

let centroid_c = north_of o 1200.

let cluster_empty () =
  check_members "no cluster for []" [] (Places.cluster []);
  check_members
    "no cluster for unpositioned, deleted, nan and infinite observations" []
    (Places.cluster unplaceable)

let cluster_single () =
  let cs = Places.cluster [a1] in
  check_members "one cluster of A1" [[a1]] cs;
  Alcotest.(check (list point)) "its centroid is A1's point" [o] (centroids cs)

let cluster_base () =
  List.iter
    (fun (name, input) ->
      let cs = Places.cluster input in
      check_members
        (Printf.sprintf "clusters A, B, C from the base set in %s" name)
        [[a1; a2; a3]; [b1; b2]; [c1]]
        cs;
      Alcotest.(check (list point))
        (Printf.sprintf "centroids of A, B, C in %s" name)
        [centroid_a; centroid_b; centroid_c]
        (centroids cs))
    [
      ("time order", base);
      ("reverse order", base_reversed);
      ("shuffled order", base_shuffled);
    ]

let cluster_unplaceable_in_none () =
  let members = List.concat (member_ids (Places.cluster base)) in
  List.iter
    (fun (name, (x : Observation.t)) ->
      Alcotest.(check bool)
        (Printf.sprintf "%s is in no cluster" name)
        false
        (List.mem (Ids.Observation_id.to_string x.id) members))
    [
      ("U1 (no position)", u1);
      ("D1 (deleted)", d1);
      ("N1 (nan)", n1);
      ("I1 (infinity)", i1);
    ]

let cluster_order_independent () =
  let reference = Places.cluster base in
  List.iter
    (fun (name, input) ->
      let cs = Places.cluster input in
      Alcotest.(check (list (list string)))
        (Printf.sprintf "%s gives the same members as time order" name)
        (member_ids reference) (member_ids cs);
      Alcotest.(check (list point))
        (Printf.sprintf "%s gives the same centroids as time order" name)
        (centroids reference) (centroids cs))
    [("reverse order", base_reversed); ("shuffled order", base_shuffled)]

let cluster_boundary () =
  let p = obs ~id:1 ~at:0 (Some o) in
  let q = obs ~id:2 ~at:1 (Some (north_of o 500.)) in
  let q' = obs ~id:3 ~at:1 (Some (north_of o 500.01)) in
  check_members "a point exactly 500 m away joins"
    [[p; q]]
    (Places.cluster [p; q]);
  check_members "a point 500.01 m away starts its own cluster" [[p]; [q']]
    (Places.cluster [p; q'])

let cluster_centroid_not_seed () =
  let p = obs ~id:1 ~at:0 (Some o) in
  let q = obs ~id:2 ~at:1 (Some (north_of o 400.)) in
  let r = obs ~id:3 ~at:2 (Some (north_of o 650.)) in
  let s = obs ~id:4 ~at:3 (Some (north_of o (-140.))) in
  let s' = obs ~id:5 ~at:3 (Some (north_of o (-160.))) in
  let pqr = Places.cluster [p; q; r] in
  check_members "R, 650 m from P but 450 m from the centroid, joins"
    [[p; q; r]]
    pqr;
  Alcotest.(check (list point))
    "centroid of P, Q, R is their mean, about 350 m north of o"
    [{lat = mean_lat [o; north_of o 400.; north_of o 650.]; lon = 5.}]
    (centroids pqr);
  check_members "S, about 490 m from the centroid, joins"
    [[p; q; r; s]]
    (Places.cluster [p; q; r; s]);
  check_members "S', about 510 m from the centroid, starts its own cluster"
    [[p; q; r]; [s']]
    (Places.cluster [p; q; r; s'])

let cluster_nearest_centroid () =
  let x = obs ~id:1 ~at:0 (Some o) in
  let y = obs ~id:2 ~at:1 (Some (north_of o 900.)) in
  let z = obs ~id:3 ~at:2 (Some (north_of o 480.)) in
  check_members "Z, 480 m from X and 420 m from Y, joins Y"
    [[x]; [y; z]]
    (Places.cluster [x; y; z])

(* On the equator, lon x and lon -x are exactly equidistant from lon 0: the
   haversine term only sees sin² of the longitude difference. *)
let cluster_exact_tie () =
  let east = Some (east_on_equator 400.) in
  let west = Some (east_on_equator (-400.)) in
  let middle = Some (east_on_equator 0.) in
  let e = obs ~id:1 ~at:0 east and w = obs ~id:2 ~at:1 west in
  let m = obs ~id:3 ~at:2 middle in
  check_members "M, 400 m from both, joins E, created first"
    [[e; m]; [w]]
    (Places.cluster [e; w; m]);
  let w' = obs ~id:1 ~at:0 west and e' = obs ~id:2 ~at:1 east in
  check_members "M joins W when W is created first"
    [[w'; m]; [e']]
    (Places.cluster [m; e'; w'])

let cluster_time_not_input_order () =
  let p = obs ~id:1 ~at:0 (Some o) in
  let r = obs ~id:2 ~at:1 (Some (north_of o 650.)) in
  let q = obs ~id:3 ~at:2 (Some (north_of o 400.)) in
  List.iter
    (fun (name, input) ->
      check_members
        (Printf.sprintf "R (earlier) starts a cluster that Q joins, %s" name)
        [[p]; [r; q]]
        (Places.cluster input))
    [
      ("time order", [p; r; q]);
      ("Q given before R", [q; p; r]);
      ("reversed", [q; r; p]);
    ]

let cluster_equal_at_by_id () =
  let p = obs ~id:1 ~at:0 (Some o) in
  let r_first = obs ~id:2 ~at:1 (Some (north_of o 650.)) in
  let q_second = obs ~id:3 ~at:1 (Some (north_of o 400.)) in
  List.iter
    (fun (name, input) ->
      check_members
        (Printf.sprintf "same at, R's id first: Q joins R, %s" name)
        [[p]; [r_first; q_second]]
        (Places.cluster input))
    [("P, R, Q", [p; r_first; q_second]); ("Q, R, P", [q_second; r_first; p])];
  let q_first = obs ~id:2 ~at:1 (Some (north_of o 400.)) in
  let r_second = obs ~id:3 ~at:1 (Some (north_of o 650.)) in
  List.iter
    (fun (name, input) ->
      check_members
        (Printf.sprintf "same at, Q's id first: all three in one place, %s" name)
        [[p; q_first; r_second]]
        (Places.cluster input))
    [("P, R, Q", [p; r_second; q_first]); ("Q, R, P", [q_first; r_second; p])]

let cluster_east_west () =
  let west = obs ~id:1 ~at:0 (Some o) in
  let east = obs ~id:2 ~at:1 (Some {o with lon = 5.002}) in
  let cs = Places.cluster [west; east] in
  check_members "two points about 157 m apart east-west are one cluster"
    [[west; east]]
    cs;
  Alcotest.(check (list point))
    "its centroid averages the longitudes"
    [{lat = 45.; lon = 5.001}]
    (centroids cs)

let cluster_duplicate_record () =
  let cs = Places.cluster [a1; a1] in
  check_members "the same record twice is two members of one cluster"
    [[a1; a1]]
    cs;
  Alcotest.(check (list point)) "its centroid is A1's point" [o] (centroids cs)

(* label *)

let named s = Some (Places.Named s)
let derived s = Some (Places.Derived s)
let at_o ?label ?derived ~id ~at () = obs ?label ?derived ~id ~at (Some o)

let label_none () =
  Alcotest.(check (option label)) "empty list" None (Places.label []);
  Alcotest.(check (option label))
    "one unpositioned unlabelled" None (Places.label [u1]);
  Alcotest.(check (option label))
    "one deleted observation labelled X" None
    (Places.label [obs ~label:"X" ~deleted:true ~id:1 ~at:0 (Some o)])

let label_plurality () =
  let three ?derived () =
    [
      at_o ~label:"Col" ?derived ~id:1 ~at:0 ();
      at_o ~label:"Col" ?derived ~id:2 ~at:1 ();
      at_o ~label:"Lac" ?derived ~id:3 ~at:2 ();
    ]
  in
  Alcotest.(check (option label))
    "Col, Col, Lac" (named "Col")
    (Places.label (three ()));
  Alcotest.(check (option label))
    "Col, Col, Lac, all with a derived name" (named "Col")
    (Places.label (three ~derived:"Près de Y" ()))

let label_one_labelled () =
  Alcotest.(check (option label))
    "one labelled among three unlabelled" (named "Col")
    (Places.label
       [
         at_o ~id:1 ~at:0 ();
         at_o ~id:2 ~at:1 ();
         at_o ~label:"Col" ~id:3 ~at:2 ();
         at_o ~id:4 ~at:3 ();
       ])

let label_deleted_ignored_in_plurality () =
  Alcotest.(check (option label))
    "two deleted X do not outvote one Col" (named "Col")
    (Places.label
       [
         obs ~label:"X" ~deleted:true ~id:1 ~at:0 (Some o);
         obs ~label:"X" ~deleted:true ~id:2 ~at:1 (Some o);
         at_o ~label:"Col" ~id:3 ~at:2 ();
       ])

let label_tie () =
  let day =
    [
      at_o ~label:"Lac" ~id:1 ~at:0 ();
      at_o ~label:"Col" ~id:2 ~at:1 ();
      at_o ~label:"Col" ~id:3 ~at:2 ();
      at_o ~label:"Lac" ~id:4 ~at:3 ();
    ]
  in
  Alcotest.(check (option label))
    "2-2 tie goes to the earliest, Lac" (named "Lac") (Places.label day);
  Alcotest.(check (option label))
    "same with the input reversed" (named "Lac")
    (Places.label (List.rev day));
  let same_at =
    [at_o ~label:"Lac" ~id:1 ~at:0 (); at_o ~label:"Col" ~id:2 ~at:0 ()]
  in
  Alcotest.(check (option label))
    "1-1 tie at the same at goes to the smaller id, Lac" (named "Lac")
    (Places.label same_at);
  Alcotest.(check (option label))
    "same with the input reversed" (named "Lac")
    (Places.label (List.rev same_at))

let label_blank_and_trim () =
  Alcotest.(check (option label))
    "blank and empty labels fall back to the derived name" (derived "Près de Y")
    (Places.label
       [
         at_o ~label:"  " ~derived:"Près de Y" ~id:1 ~at:0 ();
         at_o ~label:"" ~derived:"Près de Y" ~id:2 ~at:1 ();
       ]);
  Alcotest.(check (option label))
    "\" Col\" and \"Col \" are the same trimmed label" (named "Col")
    (Places.label
       [at_o ~label:" Col" ~id:1 ~at:0 (); at_o ~label:"Col " ~id:2 ~at:1 ()])

let label_derived () =
  Alcotest.(check (option label))
    "derived plurality: Près de A twice, Près de B once" (derived "Près de A")
    (Places.label
       [
         at_o ~derived:"Près de B" ~id:1 ~at:0 ();
         at_o ~derived:"Près de A" ~id:2 ~at:1 ();
         at_o ~derived:"Près de A" ~id:3 ~at:2 ();
       ]);
  let tie =
    [
      at_o ~derived:"Près de B" ~id:1 ~at:0 ();
      at_o ~derived:"Près de A" ~id:2 ~at:1 ();
      at_o ~derived:"Près de A" ~id:3 ~at:2 ();
      at_o ~derived:"Près de B" ~id:4 ~at:3 ();
    ]
  in
  Alcotest.(check (option label))
    "derived 2-2 tie goes to the earliest" (derived "Près de B")
    (Places.label tie);
  Alcotest.(check (option label))
    "derived tie, input reversed" (derived "Près de B")
    (Places.label (List.rev tie));
  Alcotest.(check (option label))
    "derived name is trimmed" (derived "Près de Y")
    (Places.label [at_o ~derived:"  Près de Y " ~id:1 ~at:0 ()])

let label_coordinates () =
  let p = obs ~id:1 ~at:0 (Some o) in
  let q = obs ~id:2 ~at:1 (Some (north_of o 200.)) in
  let mean : Places.point = {lat = mean_lat [o; north_of o 200.]; lon = 5.} in
  let coordinates = Some (Places.Coordinates mean) in
  Alcotest.(check (option label))
    "two unlabelled positions give their mean" coordinates
    (Places.label [p; q]);
  Alcotest.(check (option label))
    "unpositioned, nan and infinite observations do not move the mean"
    coordinates
    (Places.label [u1; p; n1; i1; q]);
  Alcotest.(check (option label))
    "a deleted labelled observation neither names nor moves the mean"
    coordinates
    (Places.label
       [
         p; obs ~label:"X" ~deleted:true ~id:3 ~at:2 (Some (north_of o 5000.)); q;
       ])

let label_coordinates_east_west () =
  let west = obs ~id:1 ~at:0 (Some o) in
  let east = obs ~id:2 ~at:1 (Some {o with lon = 5.002}) in
  Alcotest.(check (option label))
    "the mean of an east-west pair averages the longitudes"
    (Some (Places.Coordinates {lat = 45.; lon = 5.001}))
    (Places.label [west; east])

let label_blank_derived () =
  Alcotest.(check (option label))
    "blank derived names fall back to coordinates" (Some (Places.Coordinates o))
    (Places.label
       [at_o ~derived:"  " ~id:1 ~at:0 (); at_o ~derived:"" ~id:2 ~at:1 ()])

let label_without_position () =
  Alcotest.(check (option label))
    "a labelled observation without position names the group" (named "Col")
    (Places.label [obs ~label:"Col" ~id:1 ~at:0 None])

let label_case_sensitive () =
  Alcotest.(check (option label))
    "col, Col, Col gives Col" (named "Col")
    (Places.label
       [
         at_o ~label:"col" ~id:1 ~at:0 ();
         at_o ~label:"Col" ~id:2 ~at:1 ();
         at_o ~label:"Col" ~id:3 ~at:2 ();
       ]);
  Alcotest.(check (option label))
    "col then Col is a tie that goes to col" (named "col")
    (Places.label
       [at_o ~label:"col" ~id:1 ~at:0 (); at_o ~label:"Col" ~id:2 ~at:1 ()])

(* rename *)

let id_of (id : Ids.Observation_id.t) = Ids.Observation_id.to_string id

let find_result results (original : Observation.t) =
  List.find
    (fun (r : Observation.t) -> Ids.Observation_id.equal r.id original.id)
    results

(* Checks every field of [result] against [original] except [place_label]
   (set to [expected_label]) and [updated_at] (set to [expected_at]). *)
let check_unchanged msg ~(original : Observation.t) ~expected_label ~expected_at
    (result : Observation.t) =
  Alcotest.(check string)
    (msg ^ ": id unchanged") (id_of original.id) (id_of result.id);
  Alcotest.(check bool)
    (msg ^ ": plant_id unchanged")
    true
    (Option.equal Ids.Plant_id.equal original.plant_id result.plant_id);
  Alcotest.(check bool)
    (msg ^ ": at unchanged") true
    (Ptime.equal original.at result.at);
  Alcotest.(check bool)
    (msg ^ ": position unchanged")
    true
    (original.position = result.position);
  Alcotest.(check (option string))
    (msg ^ ": place_label set")
    expected_label result.place_label;
  Alcotest.(check bool)
    (msg ^ ": place_derived unchanged")
    true
    (original.place_derived = result.place_derived);
  Alcotest.(check bool)
    (msg ^ ": note unchanged") true
    (original.note = result.note);
  Alcotest.(check bool)
    (msg ^ ": created_at unchanged")
    true
    (Ptime.equal original.created_at result.created_at);
  Alcotest.(check bool)
    (msg ^ ": updated_at set to at")
    true
    (Ptime.equal expected_at result.updated_at);
  Alcotest.(check bool)
    (msg ^ ": deleted_at unchanged")
    true
    (Option.equal Ptime.equal original.deleted_at result.deleted_at)

let rename_changes_only_members_whose_label_must_differ () =
  let m1 = obs ~id:1 ~at:0 (Some o) in
  let m2 = obs ~label:"Jardin" ~id:2 ~at:1 (Some o) in
  let m3 = obs ~label:"Bois" ~id:3 ~at:2 (Some o) in
  let cluster : Places.cluster = {centroid = o; members = [m1; m2; m3]} in
  let at = time 100 in
  let result = Places.rename "Jardin" ~at cluster in
  Alcotest.(check (list string))
    "m1 and m3 only, in cluster.members order"
    [id_of m1.id; id_of m3.id]
    (ids result);
  check_unchanged "m1" ~original:m1 ~expected_label:(Some "Jardin")
    ~expected_at:at (find_result result m1);
  check_unchanged "m3" ~original:m3 ~expected_label:(Some "Jardin")
    ~expected_at:at (find_result result m3)

let rename_trims_the_name () =
  let m1 = obs ~id:1 ~at:0 (Some o) in
  let cluster : Places.cluster = {centroid = o; members = [m1]} in
  match Places.rename "  Jardin  " ~at:(time 100) cluster with
  | [r] ->
      Alcotest.(check (option string))
        "trimmed to Jardin" (Some "Jardin") r.place_label
  | results ->
      Alcotest.failf "expected exactly 1 renamed member, got %d"
        (List.length results)

let rename_noop_when_every_member_already_named () =
  let m1 = obs ~label:"Jardin" ~id:1 ~at:0 (Some o) in
  let m2 = obs ~label:"Jardin" ~id:2 ~at:1 (Some o) in
  let cluster : Places.cluster = {centroid = o; members = [m1; m2]} in
  Alcotest.(check (list string))
    "nothing to save" []
    (ids (Places.rename "Jardin" ~at:(time 100) cluster))

let rename_rewrites_a_label_differing_only_by_spaces () =
  let m1 = obs ~label:" Jardin " ~id:1 ~at:0 (Some o) in
  let cluster : Places.cluster = {centroid = o; members = [m1]} in
  match Places.rename "Jardin" ~at:(time 100) cluster with
  | [r] ->
      Alcotest.(check (option string))
        "rewritten to the trimmed label" (Some "Jardin") r.place_label
  | results ->
      Alcotest.failf "expected exactly 1 renamed member, got %d"
        (List.length results)

let rename_blank_clears_the_label () =
  let a = obs ~label:"A" ~id:1 ~at:0 (Some o) in
  let b = obs ~id:2 ~at:1 (Some o) in
  let cluster : Places.cluster = {centroid = o; members = [a; b]} in
  let at = time 100 in
  let result = Places.rename "   " ~at cluster in
  Alcotest.(check (list string))
    "only A (B is already unlabelled)"
    [id_of a.id]
    (ids result);
  check_unchanged "A" ~original:a ~expected_label:None ~expected_at:at
    (find_result result a)

let rename_blank_noop_when_every_member_already_unlabelled () =
  let a = obs ~id:1 ~at:0 (Some o) in
  let b = obs ~id:2 ~at:1 (Some o) in
  let cluster : Places.cluster = {centroid = o; members = [a; b]} in
  Alcotest.(check (list string))
    "nothing to save" []
    (ids (Places.rename "" ~at:(time 100) cluster))

let rename_result_names_the_place () =
  let m1 = obs ~id:1 ~at:0 (Some o) in
  let m2 = obs ~label:"Jardin" ~id:2 ~at:1 (Some o) in
  let m3 = obs ~label:"Bois" ~id:3 ~at:2 (Some o) in
  let cluster : Places.cluster = {centroid = o; members = [m1; m2; m3]} in
  let result = Places.rename "Jardin" ~at:(time 100) cluster in
  let replace (m : Observation.t) =
    match
      List.find_opt
        (fun (r : Observation.t) -> Ids.Observation_id.equal r.id m.id)
        result
    with
    | Some r -> r
    | None -> m
  in
  Alcotest.(check (option label))
    "the renamed cluster's label is Named Jardin" (named "Jardin")
    (Places.label (List.map replace cluster.members))

let equal_point_cases () =
  let check what expected a b =
    Alcotest.(check bool) what expected (Places.equal_point a b)
  in
  check "same coordinates" true o {lat = 45.0; lon = 5.0};
  check "another lat" false o {lat = 45.000001; lon = 5.0};
  check "another lon" false o {lat = 45.0; lon = 5.000001};
  check "nan equals nan" true
    {lat = Float.nan; lon = 5.0}
    {lat = Float.nan; lon = 5.0}

let tests =
  [
    ( "equal_point compares both coordinates with Float.equal",
      `Quick,
      equal_point_cases );
    ( "distance_m of a point to itself is 0",
      `Quick,
      distance_zero_for_equal_points );
    ("distance_m is symmetric", `Quick, distance_symmetric);
    ( "distance_m across hemispheres matches an independent haversine",
      `Quick,
      distance_across_hemispheres );
    ( "distance_m of one degree on a meridian or the equator is R·π/180",
      `Quick,
      distance_one_degree );
    ("distance_m of antipodes is π·R, not nan", `Quick, distance_antipodes);
    ( "distance_m treats lon 180 and -180 as the same meridian",
      `Quick,
      distance_antimeridian );
    ( "distance_m Paris to London is about 343.56 km",
      `Quick,
      distance_paris_london );
    ("distance_m to a point 500 m north is 500", `Quick, distance_north_500);
    ("distance_m with a nan coordinate is nan", `Quick, distance_nan);
    ( "position_point gives Some {lat; lon} for a live, placeable observation",
      `Quick,
      position_point_live );
    ( "position_point gives None for no position or a deleted observation",
      `Quick,
      position_point_unplaceable );
    ( "position_point gives None for a nan or infinite coordinate",
      `Quick,
      position_point_nonfinite );
    ("of_position drops accuracy_m", `Quick, of_position_drops_accuracy);
    ("radius_m is 500 and earth_radius_m is 6 371 000", `Quick, constants);
    ( "within is inclusive at 500 m and false beyond or on nan",
      `Quick,
      within_cases );
    ("cluster of nothing placeable is []", `Quick, cluster_empty);
    ( "cluster of one observation is one cluster at its point",
      `Quick,
      cluster_single );
    ( "cluster of the base set gives A, B, C with mean centroids",
      `Quick,
      cluster_base );
    ( "cluster leaves unplaceable observations out",
      `Quick,
      cluster_unplaceable_in_none );
    ("cluster does not depend on input order", `Quick, cluster_order_independent);
    ( "cluster joins at exactly 500 m and not at 500.01 m",
      `Quick,
      cluster_boundary );
    ( "cluster measures to the running centroid, not the first member",
      `Quick,
      cluster_centroid_not_seed );
    ("cluster joins the nearest centroid", `Quick, cluster_nearest_centroid);
    ( "cluster gives an exact tie to the earliest-created cluster",
      `Quick,
      cluster_exact_tie );
    ( "cluster processes observations by at, not input position",
      `Quick,
      cluster_time_not_input_order );
    ("cluster breaks equal at by id", `Quick, cluster_equal_at_by_id);
    ("cluster averages longitudes in the centroid", `Quick, cluster_east_west);
    ( "cluster keeps the same record twice as two members",
      `Quick,
      cluster_duplicate_record );
    ("label is None with nothing labelled or placeable", `Quick, label_none);
    ("label is the most frequent place_label", `Quick, label_plurality);
    ( "label is Named by a single labelled observation",
      `Quick,
      label_one_labelled );
    ( "label ignores deleted observations in the count",
      `Quick,
      label_deleted_ignored_in_plurality );
    ("label tie goes to the earliest label", `Quick, label_tie);
    ("label trims and treats blank as absent", `Quick, label_blank_and_trim);
    ( "label falls back to the most frequent place_derived",
      `Quick,
      label_derived );
    ( "label falls back to the mean of placeable positions",
      `Quick,
      label_coordinates );
    ( "label averages longitudes in Coordinates",
      `Quick,
      label_coordinates_east_west );
    ("label treats blank derived names as absent", `Quick, label_blank_derived);
    ( "label of a labelled observation without position is Named",
      `Quick,
      label_without_position );
    ("label compares names case-sensitively", `Quick, label_case_sensitive);
    ( "rename changes only the members whose label must differ, in order",
      `Quick,
      rename_changes_only_members_whose_label_must_differ );
    ("rename trims the given name", `Quick, rename_trims_the_name);
    ( "rename is a no-op when every member already has that name",
      `Quick,
      rename_noop_when_every_member_already_named );
    ( "rename rewrites a label differing from the trimmed name only by spaces",
      `Quick,
      rename_rewrites_a_label_differing_only_by_spaces );
    ("a blank name clears place_label", `Quick, rename_blank_clears_the_label);
    ( "a blank name is a no-op when every member is already unlabelled",
      `Quick,
      rename_blank_noop_when_every_member_already_unlabelled );
    ( "applying rename's result names the place",
      `Quick,
      rename_result_names_the_place );
  ]
