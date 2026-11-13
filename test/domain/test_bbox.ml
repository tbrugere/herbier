(* Bbox against the two folds it replaced, copied below verbatim: geo's
   Features.box_of_points (the map's bounds) and Communes' box_of and in_box
   (the commune index). Same boxes, nan and signed zeros included, and the
   same answers to "is this point in the box". *)

module Places = Herbier_domain.Places
module Bbox = Herbier_domain.Bbox

(* geo/features.ml, before Bbox. *)
type bounds = {south : float; west : float; north : float; east : float}

let box_of_points = function
  | [] -> None
  | ({lat; lon} : Places.point) :: rest ->
      Some
        (List.fold_left
           (fun {south; west; north; east} ({lat; lon} : Places.point) ->
             {
               south = Float.min south lat;
               west = Float.min west lon;
               north = Float.max north lat;
               east = Float.max east lon;
             })
           {south = lat; west = lon; north = lat; east = lon}
           rest)

(* geo/communes.ml, before Bbox, over one ring of (lon, lat). *)
type box = {min_lon : float; min_lat : float; max_lon : float; max_lat : float}

let box_of ring =
  Array.fold_left
    (fun b (lon, lat) ->
      {
        min_lon = Float.min b.min_lon lon;
        min_lat = Float.min b.min_lat lat;
        max_lon = Float.max b.max_lon lon;
        max_lat = Float.max b.max_lat lat;
      })
    {
      min_lon = Float.infinity;
      min_lat = Float.infinity;
      max_lon = Float.neg_infinity;
      max_lat = Float.neg_infinity;
    }
    ring

let in_box ?(dlon = 0.) ?(dlat = 0.) b ({lat; lon} : Places.point) =
  b.min_lon -. dlon <= lon
  && lon <= b.max_lon +. dlon
  && b.min_lat -. dlat <= lat
  && lat <= b.max_lat +. dlat

(* nan equals nan, and -0. differs from 0. *)
let same a b =
  Float.equal a b && Bool.equal (Float.sign_bit a) (Float.sign_bit b)

let sides = function
  | None -> "None"
  | Some (s, w, n, e) -> Printf.sprintf "Some {%h; %h; %h; %h}" s w n e

let sides_of_bbox =
  Option.map (fun ({south; west; north; east} : Bbox.t) ->
      (south, west, north, east))

let same_sides a b =
  match (a, b) with
  | None, None -> true
  | Some (s, w, n, e), Some (s', w', n', e') ->
      same s s' && same w w' && same n n' && same e e'
  | None, Some _ | Some _, None -> false

let p lat lon : Places.point = {lat; lon}

let point_sets =
  [
    ("no point", []);
    ("one point", [p 48.1 7.2]);
    ("several", [p 48.1 7.2; p 47.9 7.5; p 48.3 6.9]);
    ("nan first", [p Float.nan 7.2; p 48. 7.]);
    ("nan in the middle", [p 48. 7.; p 48.5 Float.nan; p 47. 8.]);
    ("infinite", [p 48. Float.infinity; p 47. 7.]);
    ("signed zeros", [p 0. (-0.); p (-0.) 0.]);
    ("negative zero alone", [p (-0.) (-0.)]);
  ]

let probes =
  [
    p 48.1 7.2;
    p 47.9 7.5;
    p 48.0 7.0;
    p 50. 7.;
    p Float.nan 7.;
    p 48. Float.nan;
    p 0. 0.;
    p (-0.) (-0.);
    p 48.2 Float.infinity;
  ]

let features_case (name, points) =
  ( "Features.box_of_points: " ^ name,
    `Quick,
    fun () ->
      let old =
        Option.map
          (fun {south; west; north; east} -> (south, west, north, east))
          (box_of_points points)
      and now = sides_of_bbox (Bbox.of_points points) in
      match same_sides old now with
      | true -> ()
      | false ->
          Alcotest.failf "%s: was %s, now %s" name (sides old) (sides now) )

let communes_case (name, points) =
  ( "Communes.box_of and in_box: " ^ name,
    `Quick,
    fun () ->
      let ring =
        Array.of_list
          (List.map (fun ({lat; lon} : Places.point) -> (lon, lat)) points)
      in
      let old = box_of ring and now = Bbox.of_points points in
      (match (points, now) with
      | [], None -> ()
      | _ :: _, Some _ -> (
          let old_sides =
            Some (old.min_lat, old.min_lon, old.max_lat, old.max_lon)
          in
          match same_sides old_sides (sides_of_bbox now) with
          | true -> ()
          | false ->
              Alcotest.failf "%s: was %s, now %s" name (sides old_sides)
                (sides (sides_of_bbox now)))
      | [], Some _ | _ :: _, None -> Alcotest.failf "%s: box presence" name);
      List.iter
        (fun ({lat; lon} as q : Places.point) ->
          List.iter
            (fun (dlat, dlon) ->
              let was = in_box ~dlon ~dlat old q
              and is =
                match now with
                | None -> false
                | Some b -> Bbox.contains ~dlat ~dlon b q
              in
              Alcotest.(check bool)
                (Printf.sprintf "%s: (%h, %h) grown by (%g, %g)" name lat lon
                   dlat dlon)
                was is)
            [(0., 0.); (0.5, 0.5); (0., 1.)])
        probes )

let tests =
  List.map features_case point_sets @ List.map communes_case point_sets
