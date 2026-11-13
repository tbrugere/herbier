type point = {
  lat : float; [@equal Float.equal]
  lon : float; [@equal Float.equal]
}
[@@deriving eq]

let of_position ({lat; lon; accuracy_m = _} : Observation.position) = {lat; lon}
let earth_radius_m = 6_371_000.
let radius_m = 500.
let radians degrees = degrees *. Float.pi /. 180.

let distance_m {lat = lat1; lon = lon1} {lat = lat2; lon = lon2} =
  let phi1 = radians lat1 and phi2 = radians lat2 in
  let sin_half_dphi = Float.sin ((phi2 -. phi1) /. 2.)
  and sin_half_dlambda = Float.sin (radians (lon2 -. lon1) /. 2.) in
  let a =
    (sin_half_dphi *. sin_half_dphi)
    +. (Float.cos phi1 *. Float.cos phi2 *. sin_half_dlambda *. sin_half_dlambda)
  in
  (* Rounding can push [a] just above 1 near antipodes, where [sqrt (1 - a)]
     would be [nan]; the lower clamp only matters for out-of-range latitudes.
     [Float.min]/[max] propagate [nan], so a [nan] coordinate still gives
     [nan]. *)
  let a = Float.min 1. (Float.max 0. a) in
  2. *. earth_radius_m *. Float.atan2 (Float.sqrt a) (Float.sqrt (1. -. a))

(* The 1 mm makes the exact-500 m case independent of last-ulp differences
   between libm and JS Math. *)
let within a b = distance_m a b <= radius_m +. 1e-3

type cluster = {centroid : point; members : Observation.t list}
type label = Named of string | Derived of string | Coordinates of point

let compare_obs (a : Observation.t) (b : Observation.t) =
  match Ptime.compare a.at b.at with
  | 0 -> Ids.Observation_id.compare a.id b.id
  | c -> c

let finite {lat; lon} = Float.is_finite lat && Float.is_finite lon

let position_point : Observation.t -> point option = function
  | {deleted_at = None; position = Some {lat; lon; accuracy_m = _}; _}
    when finite {lat; lon} ->
      Some {lat; lon}
  | {deleted_at = Some _ | None; position = Some _ | None; _} -> None

(* A cluster being built: running sums keep each join O(1). *)
type group = {
  sum_lat : float;
  sum_lon : float;
  count : int;
  rev_members : Observation.t list;
}

let mean_of ~sum_lat ~sum_lon count =
  let n = Float.of_int count in
  {lat = sum_lat /. n; lon = sum_lon /. n}

let centroid {sum_lat; sum_lon; count; rev_members = _} =
  mean_of ~sum_lat ~sum_lon count

(* Index of the group whose centroid is nearest among those within [p].
   [groups] is newest first, so replacing on [d <= d_best] hands an exact tie
   to the earliest-created group. *)
let nearest p groups =
  let step (i, best) g =
    let c = centroid g in
    let d = distance_m p c in
    let best =
      if not (within p c) then best
      else
        match best with
        | Some (_, d_best) when d > d_best -> best
        | Some _ | None -> Some (i, d)
    in
    (i + 1, best)
  in
  List.fold_left step (0, None) groups |> snd |> Option.map fst

let join g o {lat; lon} =
  {
    sum_lat = g.sum_lat +. lat;
    sum_lon = g.sum_lon +. lon;
    count = g.count + 1;
    rev_members = o :: g.rev_members;
  }

let add groups (o, p) =
  match nearest p groups with
  | None ->
      {sum_lat = p.lat; sum_lon = p.lon; count = 1; rev_members = [o]} :: groups
  | Some k -> List.mapi (fun i g -> if i = k then join g o p else g) groups

let cluster observations =
  observations
  |> List.filter_map (fun o -> Option.map (fun p -> (o, p)) (position_point o))
  |> List.stable_sort (fun (a, _) (b, _) -> compare_obs a b)
  |> List.fold_left add []
  |> List.rev_map (fun g ->
      {centroid = centroid g; members = List.rev g.rev_members})

let place_name (o : Observation.t) =
  match Option.bind o.place_label Text.non_blank with
  | Some l -> Some l
  | None -> Option.bind o.place_derived Text.non_blank

let unknown_name = "Lieu inconnu"

let display_name (o : Observation.t) =
  match (place_name o, o.position) with
  | Some s, _ -> Some s
  | None, Some _ -> Some unknown_name
  | None, None -> None

let point_text {lat; lon} = Printf.sprintf "%.4f, %.4f" lat lon

(* [labels] in time order. Counts are keyed by label with the rank of the
   label's first appearance, which breaks frequency ties. An association list
   is quadratic in distinct labels, and a day or a place has only a few. *)
let plurality labels =
  let tally counts (rank, s) =
    match List.assoc_opt s counts with
    | Some (n, first) -> (s, (n + 1, first)) :: List.remove_assoc s counts
    | None -> (s, (1, rank)) :: counts
  in
  let better (_, (n, rank)) (_, (n', rank')) =
    n > n' || (n = n' && rank < rank')
  in
  let pick best c =
    match best with
    | Some b when not (better c b) -> best
    | Some _ | None -> Some c
  in
  labels
  |> List.mapi (fun rank s -> (rank, s))
  |> List.fold_left tally []
  |> List.fold_left pick None
  |> Option.map fst

let mean = function
  | [] -> None
  | points ->
      let sum_lat, sum_lon =
        List.fold_left
          (fun (la, lo) {lat; lon} -> (la +. lat, lo +. lon))
          (0., 0.) points
      in
      Some (mean_of ~sum_lat ~sum_lon (List.length points))

let label observations =
  let live =
    observations
    |> List.filter (fun (o : Observation.t) -> Option.is_none o.deleted_at)
    |> List.stable_sort compare_obs
  in
  let most_frequent field =
    live
    |> List.filter_map (fun o -> Option.bind (field o) Text.non_blank)
    |> plurality
  in
  match most_frequent (fun (o : Observation.t) -> o.place_label) with
  | Some s -> Some (Named s)
  | None -> (
      match most_frequent (fun (o : Observation.t) -> o.place_derived) with
      | Some s -> Some (Derived s)
      | None ->
          live
          |> List.filter_map position_point
          |> mean
          |> Option.map (fun c -> Coordinates c))

let rename name ~at {centroid = _; members} =
  let label = Text.non_blank name in
  List.filter_map
    (fun (o : Observation.t) ->
      match Option.equal String.equal o.place_label label with
      | true -> None
      | false -> Some {o with place_label = label; updated_at = at})
    members
