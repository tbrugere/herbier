module Places = Herbier_domain.Places

let layer = "ADMINEXPRESS-COG-CARTO.LATEST"

module Code = struct
  type t = string

  let is_digit = function '0' .. '9' -> true | _ -> false

  (* Mainland codes skip 20 (split into 2A and 2B in 1976); overseas ones
     are 971 to 976. *)
  let valid code =
    match code with
    | "2A" | "2B" -> true
    | _ when String.length code = 2 && String.for_all is_digit code ->
        let n = int_of_string code in
        1 <= n && n <= 95 && n <> 20
    | _ when String.length code = 3 -> (
        match (String.sub code 0 2, code.[2]) with
        | "97", '1' .. '6' -> true
        | _ -> false)
    | _ -> false

  let of_string code = match valid code with true -> Some code | false -> None
  let to_string code = code
  let equal = String.equal
  let compare = String.compare
end

type departement = {code : Code.t; name : string} [@@deriving eq]

(* No département has close to this many communes (Pas-de-Calais: 887): a
   page this full is taken as truncated. *)
let count = 5000

let wfs ~typename ~properties extra =
  Geocode.geoplateforme_wfs
    ([
       ("SERVICE", "WFS");
       ("VERSION", "2.0.0");
       ("REQUEST", "GetFeature");
       ("OUTPUTFORMAT", "application/json");
       ("TYPENAMES", layer ^ ":" ^ typename);
       ("PROPERTYNAME", properties);
       ("SORTBY", "code_insee");
       ("COUNT", string_of_int count);
     ]
    @ extra)

let departements_request =
  wfs ~typename:"departement" ~properties:"code_insee,nom_officiel" []

let member = Geocode.member
let properties = Geocode.properties
let features = Geocode.features
let name_of props = Geocode.string "nom_officiel" props

let code_of props =
  match member "code_insee" props with Some (`String s) -> Some s | _ -> None

let departement feature =
  let props = properties feature in
  match (Option.bind (code_of props) Code.of_string, name_of props) with
  | Some code, Some name -> Some {code; name}
  | _ -> None

let departements json =
  Result.map
    (fun features ->
      features
      |> List.filter_map departement
      |> List.stable_sort (fun a b -> Code.compare a.code b.code)
      |> List.fold_left
           (fun acc d ->
             match acc with
             | prev :: _ when Code.equal prev.code d.code -> acc
             | _ -> d :: acc)
           []
      |> List.rev)
    (features json)

let available ~downloaded =
  List.filter (fun d -> not (List.exists (Code.equal d.code) downloaded))

type ring = ((float[@equal Float.equal]) * (float[@equal Float.equal])) array
[@@deriving eq]

type commune = {insee : string; name : string; polygons : ring list list}
[@@deriving eq]

type pack = {departement : Code.t; communes : commune list} [@@deriving eq]

let tolerance_m = 20.
let edge_m = 50.

let communes_request ~departement =
  wfs ~typename:"commune" ~properties:"code_insee,nom_officiel,geometrie"
    [
      ( "CQL_FILTER",
        Printf.sprintf "code_insee_du_departement='%s'"
          (Code.to_string departement) );
    ]

let metres_per_degree = Float.pi *. Places.earth_radius_m /. 180.

(* Distance in metres from (px, py) to the segment (ax, ay)-(bx, by), all in
   a local metric projection. *)
let segment_distance (px, py) (ax, ay) (bx, by) =
  let dx = bx -. ax and dy = by -. ay in
  let len2 = (dx *. dx) +. (dy *. dy) in
  let t =
    match len2 > 0. with
    | false -> 0.
    | true ->
        Float.max 0.
          (Float.min 1. ((((px -. ax) *. dx) +. ((py -. ay) *. dy)) /. len2))
  in
  let x = ax +. (t *. dx) -. px and y = ay +. (t *. dy) -. py in
  Float.sqrt ((x *. x) +. (y *. y))

let simplify ~tolerance_m (ring : ring) =
  let n = Array.length ring in
  match n < 4 with
  | true -> ring
  | false -> (
      let lon0, lat0 = ring.(0) in
      let c = Float.cos (lat0 *. Float.pi /. 180.) in
      let xy =
        Array.map
          (fun (lon, lat) ->
            ( (lon -. lon0) *. c *. metres_per_degree,
              (lat -. lat0) *. metres_per_degree ))
          ring
      in
      (* Index i of the closed ring, n standing for 0 again. *)
      let at i = xy.(i mod n) in
      let far =
        let rec go i (best, best_i) =
          match i >= n with
          | true -> best_i
          | false ->
              let x, y = xy.(i) in
              let d = (x *. x) +. (y *. y) in
              go (i + 1)
                (match d > best with true -> (d, i) | false -> (best, best_i))
        in
        go 1 (-1., 0)
      in
      (* style: a keep array local to this call, filled by the recursion. *)
      let keep = Array.make n false in
      let rec dp first last =
        match last - first < 2 with
        | true -> ()
        | false -> (
            let a = at first and b = at last in
            let rec farthest i (best, best_i) =
              match i >= last with
              | true -> (best, best_i)
              | false ->
                  let d = segment_distance (at i) a b in
                  farthest (i + 1)
                    (match d > best with
                    | true -> (d, i)
                    | false -> (best, best_i))
            in
            let d, i = farthest (first + 1) (-1., first) in
            match d > tolerance_m with
            | false -> ()
            | true ->
                keep.(i mod n) <- true;
                dp first i;
                dp i last)
      in
      keep.(0) <- true;
      keep.(far) <- true;
      dp 0 far;
      dp far n;
      let out =
        Array.of_list
          (List.rev
             (snd
                (Array.fold_left
                   (fun (i, acc) v ->
                     match keep.(i) with
                     | true -> (i + 1, v :: acc)
                     | false -> (i + 1, acc))
                   (0, []) ring)))
      in
      match Array.length out < 3 with true -> ring | false -> out)

let number = Geocode.number
let grid v = Float.round (v *. 1e5) /. 1e5

(* All of a list or nothing. Tail-recursive: a ring has thousands of
   vertices. *)
let all f l =
  let rec go acc = function
    | [] -> Some (List.rev acc)
    | x :: rest -> (
        match f x with Some y -> go (y :: acc) rest | None -> None)
  in
  go [] l

let vertex = function
  | `List (lon :: lat :: _) -> (
      match (number lon, number lat) with
      | Some lon, Some lat -> Some (grid lon, grid lat)
      | _ -> None)
  | _ -> None

let same (x, y) (x', y') = Float.equal x x' && Float.equal y y'

(* A ring or polygon that decoded but is too small to keep, or kept. *)
type 'a part = Dropped | Kept of 'a

(* Rounded vertices without consecutive duplicates nor the closing one;
   [None] for a malformed ring. *)
let raw_ring = function
  | `List vertices -> (
      match all vertex vertices with
      | None -> None
      | Some vs -> (
          let deduped =
            List.rev
              (List.fold_left
                 (fun acc v ->
                   match acc with
                   | prev :: _ when same prev v -> acc
                   | _ -> v :: acc)
                 [] vs)
          in
          let open_ring =
            match (deduped, List.rev deduped) with
            | first :: _, last :: rest_rev when same first last ->
                List.rev rest_rev
            | _ -> deduped
          in
          match List.length open_ring < 3 with
          | true -> Some Dropped
          | false -> Some (Kept (Array.of_list open_ring))))
  | _ -> None

let kept = function Kept p -> Some p | Dropped -> None

let polygon = function
  | `List rings -> (
      match all raw_ring rings with
      | None -> None
      | Some (Dropped :: _) | Some [] -> Some Dropped
      | Some (Kept outer :: holes) ->
          Some
            (Kept
               (List.map (simplify ~tolerance_m)
                  (outer :: List.filter_map kept holes))))
  | _ -> None

let geometry feature =
  match member "geometry" feature with
  | None -> None
  | Some g -> (
      match (member "type" g, member "coordinates" g) with
      | Some (`String "MultiPolygon"), Some (`List polygons) ->
          Option.map (List.filter_map kept) (all polygon polygons)
      | Some (`String "Polygon"), Some coordinates ->
          Option.map (fun p -> Option.to_list (kept p)) (polygon coordinates)
      | _ -> None)

let commune feature =
  let props = properties feature in
  match (code_of props, name_of props, geometry feature) with
  | Some insee, Some name, Some (_ :: _ as polygons)
    when String.length insee = 5 ->
      Some {insee; name; polygons}
  | _ -> None

let pack_of_payload ~departement json =
  match features json with
  | Error e -> Error e
  | Ok features -> (
      let returned = List.length features in
      match member "numberMatched" json with
      | Some (`Int n) when n > returned ->
          Error
            (Geocode.Unexpected
               {path = "/numberMatched"; expected = "all features in one page"})
      | _ when returned >= count ->
          Error
            (Geocode.Unexpected
               {path = "/features"; expected = "fewer than COUNT features"})
      | _ -> (
          match List.filter_map commune features with
          | [] ->
              Error
                (Geocode.Unexpected
                   {path = "/features"; expected = "at least one commune"})
          | communes ->
              Ok
                {
                  departement;
                  communes =
                    List.stable_sort
                      (fun a b -> String.compare a.insee b.insee)
                      communes;
                }))

let fixed v = `Int (Float.to_int (Float.round (v *. 1e5)))

let ring_json (r : ring) =
  `List
    (Array.fold_right
       (fun (lon, lat) acc -> fixed lon :: fixed lat :: acc)
       r [])

let to_string p =
  Yojson.Safe.to_string
    (`Assoc
       [
         ("format", `Int 1);
         ("layer", `String layer);
         ("departement", `String (Code.to_string p.departement));
         ("tolerance_m", `Int (Float.to_int tolerance_m));
         ( "communes",
           `List
             (List.map
                (fun c ->
                  `Assoc
                    [
                      ("insee", `String c.insee);
                      ("name", `String c.name);
                      ( "polygons",
                        `List
                          (List.map
                             (fun rings -> `List (List.map ring_json rings))
                             c.polygons) );
                    ])
                p.communes) );
       ])

(* Strict decoding of our own file: the first malformed field is the
   error. *)
let unexpected path expected = Error (Geocode.Unexpected {path; expected})

let all_indexed path f l =
  let open Result.Syntax in
  let+ rev =
    List.fold_left
      (fun acc x ->
        let* i, acc = acc in
        let+ y = f (Printf.sprintf "%s/%d" path i) x in
        (i + 1, y :: acc))
      (Ok (0, []))
      l
  in
  List.rev (snd rev)

let stored_ring path = function
  | `List values -> (
      let n = List.length values in
      match n mod 2 = 0 && n >= 6 with
      | false -> unexpected path "an even list of at least 6 integers"
      | true -> (
          match all (function `Int i -> Some i | _ -> None) values with
          | None -> unexpected path "integers"
          | Some ints ->
              let rec pairs acc = function
                | x :: y :: rest ->
                    pairs
                      ((Float.of_int x /. 1e5, Float.of_int y /. 1e5) :: acc)
                      rest
                | [] | [_] -> List.rev acc
              in
              Ok (Array.of_list (pairs [] ints))))
  | _ -> unexpected path "array"

let stored_polygon path = function
  | `List (_ :: _ as rings) -> all_indexed path stored_ring rings
  | _ -> unexpected path "a non-empty array"

let stored_string path field json =
  match member field json with
  | Some (`String s) -> Ok s
  | _ -> unexpected (path ^ "/" ^ field) "string"

let stored_commune path json =
  let open Result.Syntax in
  let* insee = stored_string path "insee" json in
  let* name = stored_string path "name" json in
  let* polygons =
    match member "polygons" json with
    | Some (`List (_ :: _ as polygons)) ->
        all_indexed (path ^ "/polygons") stored_polygon polygons
    | _ -> unexpected (path ^ "/polygons") "a non-empty array"
  in
  Ok {insee; name; polygons}

let of_string s =
  let open Result.Syntax in
  let* json = Geocode.json_of_string s in
  let* () =
    match member "format" json with
    | Some (`Int 1) -> Ok ()
    | _ -> unexpected "/format" "1"
  in
  let* departement =
    let* code = stored_string "" "departement" json in
    match Code.of_string code with
    | Some code -> Ok code
    | None -> unexpected "/departement" "a département code"
  in
  let* communes =
    match member "communes" json with
    | Some (`List (_ :: _ as communes)) ->
        all_indexed "/communes" stored_commune communes
    | _ -> unexpected "/communes" "a non-empty array"
  in
  Ok {departement; communes}

type box = {min_lon : float; min_lat : float; max_lon : float; max_lat : float}
type entry = {commune : commune; box : box}
type t = (Code.t * entry list) list

let empty = []

let box_of c =
  List.fold_left
    (fun b rings ->
      List.fold_left
        (fun b ring ->
          Array.fold_left
            (fun b (lon, lat) ->
              {
                min_lon = Float.min b.min_lon lon;
                min_lat = Float.min b.min_lat lat;
                max_lon = Float.max b.max_lon lon;
                max_lat = Float.max b.max_lat lat;
              })
            b ring)
        b rings)
    {
      min_lon = Float.infinity;
      min_lat = Float.infinity;
      max_lon = Float.neg_infinity;
      max_lat = Float.neg_infinity;
    }
    c.polygons

let remove t code = List.filter (fun (c, _) -> not (Code.equal c code)) t

let add t p =
  List.stable_sort
    (fun (a, _) (b, _) -> Code.compare a b)
    (( p.departement,
       List.map (fun c -> {commune = c; box = box_of c}) p.communes )
    :: remove t p.departement)

let departements_of t = List.map fst t

let in_box ?(dlon = 0.) ?(dlat = 0.) b ({lat; lon} : Places.point) =
  b.min_lon -. dlon <= lon
  && lon <= b.max_lon +. dlon
  && b.min_lat -. dlat <= lat
  && lat <= b.max_lat +. dlat

(* Half-open ray casting towards +lon: an edge's lower end counts, its upper
   end does not, so a point on a shared edge lands on one side at most. *)
let crossings (ring : ring) ({lat = py; lon = px} : Places.point) =
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

let ring_distance ~c (p : Places.point) (ring : ring) =
  let proj (lon, lat) =
    ( (lon -. p.lon) *. c *. metres_per_degree,
      (lat -. p.lat) *. metres_per_degree )
  in
  let n = Array.length ring in
  let rec go i best =
    match i >= n with
    | true -> best
    | false ->
        go (i + 1)
          (Float.min best
             (segment_distance (0., 0.)
                (proj ring.(i))
                (proj ring.((i + 1) mod n))))
  in
  go 0 Float.infinity

let nearest t (p : Places.point) =
  let c = Float.max 0.01 (Float.cos (p.lat *. Float.pi /. 180.)) in
  let dlat = edge_m /. metres_per_degree in
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

let find t (p : Places.point) =
  match Float.is_finite p.lat && Float.is_finite p.lon with
  | false -> None
  | true -> (
      let inside e =
        in_box e.box p
        && List.exists (fun rings -> contains rings p) e.commune.polygons
      in
      match List.find_opt inside (entries t) with
      | Some e -> Some e.commune
      | None -> nearest t p)

let name t p = Option.bind (find t p) (fun c -> Geocode.near c.name)
