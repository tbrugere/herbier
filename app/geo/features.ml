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

let point_geometry p =
  `Assoc [("type", `String "Point"); ("coordinates", position p)]

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
      feature (point_geometry p)
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

type place = {
  key : Observation_id.t;
  cluster : Places.cluster;
  shown : Observation.t list;
}

let places ~keep list =
  Places.cluster list
  |> List.filter_map (fun (cluster : Places.cluster) ->
      match (cluster.members, List.filter (keep cluster) cluster.members) with
      | _, [] | [], _ :: _ -> None
      | (first : Observation.t) :: _, shown ->
          Some {key = first.id; cluster; shown})

let find places id =
  List.find_opt
    (fun {cluster; key = _; shown = _} ->
      List.exists
        (fun (o : Observation.t) -> Observation_id.equal o.id id)
        cluster.members)
    places

let count_key = "count"
let identified_key = "identified"
let role_key = "role"
let west_key = "west"
let south_key = "south"
let east_key = "east"
let north_key = "north"

let finite_point ({lat; lon} : Places.point) =
  Float.is_finite lat && Float.is_finite lon

let place_point {key; cluster; shown} =
  match (bounds shown, finite_point cluster.centroid) with
  | None, _ | Some _, false -> None
  | Some {south; west; north; east}, true ->
      let identified =
        List.length
          (List.filter
             (fun (o : Observation.t) -> Option.is_some o.plant_id)
             shown)
      in
      Some
        (feature
           (point_geometry cluster.centroid)
           [
             ("id", `String (Observation_id.to_string key));
             (count_key, `Int (List.length shown));
             (identified_key, `Int identified);
             (west_key, `Float west);
             (south_key, `Float south);
             (east_key, `Float east);
             (north_key, `Float north);
           ])

let place_points places = collection (List.filter_map place_point places)

let role_feature id role p =
  feature (point_geometry p)
    [("id", `String (Observation_id.to_string id)); (role_key, `String role)]

let selection = function
  | None -> empty
  | Some {key; cluster; shown} ->
      let members =
        (* [shown] keeps [cluster.members]' order, which is compare_obs. *)
        placed shown
        |> List.map (fun ((o : Observation.t), p) ->
            role_feature o.id "member" p)
      in
      collection (role_feature key "place" cluster.centroid :: members)

type hit = Group of bounds | Member of Observation_id.t

let number = function
  | `Int i -> Some (Float.of_int i)
  | `Float f when Float.is_finite f -> Some f
  | _ -> None

let hit = function
  | `Assoc fields -> (
      let field k = List.assoc_opt k fields in
      let bound k = Option.bind (field k) number in
      match field "cluster" with
      | Some (`Bool true) -> (
          match
            (bound west_key, bound south_key, bound east_key, bound north_key)
          with
          | Some west, Some south, Some east, Some north ->
              Some (Group {south; west; north; east})
          | _ -> None)
      | _ -> (
          match field "id" with
          | Some (`String s) ->
              Option.map (fun id -> Member id) (Observation_id.of_string s)
          | _ -> None))
  | _ -> None
