module Places = Herbier_domain.Places
module Bbox = Herbier_domain.Bbox

let edge_m = 50.

type entry = {commune : Pack.commune; box : Bbox.t option}
type t = (Code.t * entry list) list

let empty = []

let box_of (c : Pack.commune) =
  let extend b (lon, lat) : Bbox.t option =
    let p : Places.point = {lat; lon} in
    match b with
    | None -> Some (Bbox.of_point p)
    | Some b -> Some (Bbox.extend b p)
  in
  List.fold_left
    (fun b rings ->
      List.fold_left (fun b ring -> Array.fold_left extend b ring) b rings)
    None c.polygons

let remove t code = List.filter (fun (c, _) -> not (Code.equal c code)) t

let add t (p : Pack.t) =
  List.stable_sort
    (fun (a, _) (b, _) -> Code.compare a b)
    (( p.departement,
       List.map (fun c -> {commune = c; box = box_of c}) p.communes )
    :: remove t p.departement)

let departements_of t = List.map fst t

(* A commune without a point (none passes the pack decoder) has no box and
   contains nothing. *)
let in_box ?dlon ?dlat b p =
  match b with None -> false | Some b -> Bbox.contains ?dlat ?dlon b p

(* Half-open ray casting towards +lon: an edge's lower end counts, its upper
   end does not, so a point on a shared edge lands on one side at most. *)
let crossings (ring : Pack.ring) ({lat = py; lon = px} : Places.point) =
  let n = Array.length ring in
  let rec go i inside =
    match i >= n with
    | true -> inside
    | false ->
        let xi, yi = ring.(i) and xj, yj = ring.((i + n - 1) mod n) in
        let crosses =
          yi > py <> (yj > py)
          && px < ((xj -. xi) *. (py -. yi) /. (yj -. yi)) +. xi
        in
        go (i + 1) (inside <> crosses)
  in
  go 0 false

let contains rings p =
  List.fold_left (fun inside ring -> inside <> crossings ring p) false rings

let entries t = List.concat_map snd t

let ring_distance ~c (p : Places.point) (ring : Pack.ring) =
  let proj (lon, lat) =
    ( (lon -. p.lon) *. c *. Simplify.metres_per_degree,
      (lat -. p.lat) *. Simplify.metres_per_degree )
  in
  let n = Array.length ring in
  let rec go i best =
    match i >= n with
    | true -> best
    | false ->
        go (i + 1)
          (Float.min best
             (Simplify.segment_distance (0., 0.)
                (proj ring.(i))
                (proj ring.((i + 1) mod n))))
  in
  go 0 Float.infinity

let nearest t (p : Places.point) =
  let c = Float.max 0.01 (Float.cos (p.lat *. Float.pi /. 180.)) in
  let dlat = edge_m /. Simplify.metres_per_degree in
  let dlon = dlat /. c in
  let candidates =
    List.filter (fun e -> in_box ~dlon ~dlat e.box p) (entries t)
  in
  List.fold_left
    (fun best e ->
      let d =
        List.fold_left
          (fun d rings ->
            List.fold_left
              (fun d ring -> Float.min d (ring_distance ~c p ring))
              d rings)
          Float.infinity e.commune.polygons
      in
      match best with
      | Some (_, bd) when bd <= d -> best
      | Some _ | None -> (
          match d <= edge_m with true -> Some (e.commune, d) | false -> best))
    None candidates
  |> Option.map fst

(* The commune for [p], and whether one of its polygons contains [p] ([true])
   or it is only the nearest within [edge_m] ([false]). *)
let locate t (p : Places.point) =
  match Places.finite p with
  | false -> None
  | true -> (
      let inside e =
        in_box e.box p
        && List.exists (fun rings -> contains rings p) e.commune.polygons
      in
      match List.find_opt inside (entries t) with
      | Some e -> Some (e.commune, true)
      | None -> Option.map (fun c -> (c, false)) (nearest t p))

let find t p = Option.map fst (locate t p)

(* « À » only when a polygon contains the point: a commune taken by
   distance (a sliver, or just outside a pack's outer edge) is « Près de ». *)
let name t p =
  Option.bind (locate t p) (fun ((c : Pack.commune), inside) ->
      match inside with
      | true -> Near.inside c.name
      | false -> Near.phrase c.name)
