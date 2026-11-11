module Observation = Herbier_domain.Observation
module Places = Herbier_domain.Places
module Observation_id = Herbier_domain.Ids.Observation_id

let collection features =
  `Assoc [("type", `String "FeatureCollection"); ("features", `List features)]

let empty = collection []

let feature geometry properties =
  `Assoc
    [
      ("type", `String "Feature");
      ("geometry", geometry);
      ("properties", `Assoc properties);
    ]

let position ({lat; lon} : Places.point) = `List [`Float lon; `Float lat]

let placed observations =
  observations
  |> List.filter_map (fun o ->
      Option.map (fun p -> (o, p)) (Places.position_point o))

type kind = Identified | To_identify

let kind_key = "kind"

let kind_to_string = function
  | Identified -> "identified"
  | To_identify -> "to_identify"

let kind (o : Observation.t) =
  match o.plant_id with Some _ -> Identified | None -> To_identify

let observations list =
  placed list
  |> List.stable_sort (fun (a, _) (b, _) -> Places.compare_obs a b)
  |> List.map (fun ((o : Observation.t), p) ->
      feature
        (`Assoc [("type", `String "Point"); ("coordinates", position p)])
        [
          ("id", `String (Observation_id.to_string o.id));
          (kind_key, `String (kind_to_string (kind o)));
        ])
  |> collection

type bounds = {south : float; west : float; north : float; east : float}

let bounds list =
  let widen b ({lat; lon} : Places.point) =
    match b with
    | None -> Some {south = lat; west = lon; north = lat; east = lon}
    | Some {south; west; north; east} ->
        Some
          {
            south = Float.min south lat;
            west = Float.min west lon;
            north = Float.max north lat;
            east = Float.max east lon;
          }
  in
  placed list |> List.map snd |> List.fold_left widen None

let radians d = d *. Float.pi /. 180.
let degrees r = r *. 180. /. Float.pi

(* Destination point on a sphere given a start, an initial bearing and an
   angular distance. *)
let destination ({lat; lon} : Places.point) ~angle ~bearing : Places.point =
  let phi1 = radians lat and lambda1 = radians lon in
  (* Rounding can push the sine just past 1 near a pole: clamp it. *)
  let phi2 =
    Float.asin
      (Float.max (-1.)
         (Float.min 1.
            ((Float.sin phi1 *. Float.cos angle)
            +. (Float.cos phi1 *. Float.sin angle *. Float.cos bearing))))
  in
  let lambda2 =
    lambda1
    +. Float.atan2
         (Float.sin bearing *. Float.sin angle *. Float.cos phi1)
         (Float.cos angle -. (Float.sin phi1 *. Float.sin phi2))
  in
  {lat = degrees phi2; lon = degrees lambda2}

let circle ~(center : Places.point) ~radius_m ~steps =
  match
    Float.is_finite radius_m
    && radius_m > 0.
    && steps >= 3
    && Float.is_finite center.lat
    && Float.is_finite center.lon
  with
  | false -> empty
  | true ->
      let angle = radius_m /. Places.earth_radius_m in
      (* Vertex [steps] is vertex 0 again: the ring is closed. *)
      let ring =
        List.init (steps + 1) (fun i ->
            let bearing =
              2. *. Float.pi *. Float.of_int (i mod steps) /. Float.of_int steps
            in
            position (destination center ~angle ~bearing))
      in
      collection
        [
          feature
            (`Assoc
               [
                 ("type", `String "Polygon"); ("coordinates", `List [`List ring]);
               ])
            [];
        ]
