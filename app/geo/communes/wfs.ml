module Json = Herbier_net.Json

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
       ("TYPENAMES", Pack.layer ^ ":" ^ typename);
       ("PROPERTYNAME", properties);
       ("SORTBY", "code_insee");
       ("COUNT", string_of_int count);
     ]
    @ extra)

let departements_request =
  wfs ~typename:"departement" ~properties:"code_insee,nom_officiel" []

let properties = Geocode.properties
let features = Geocode.features
let name_of props = Geocode.string "nom_officiel" props

let code_of props =
  match Json.member "code_insee" props with
  | Some (`String s) -> Some s
  | _ -> None

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

let communes_request ~departement =
  wfs ~typename:"commune" ~properties:"code_insee,nom_officiel,geometrie"
    [
      ( "CQL_FILTER",
        Printf.sprintf "code_insee_du_departement='%s'"
          (Code.to_string departement) );
    ]

let grid v = Float.round (v *. 1e5) /. 1e5

let vertex = function
  | `List (lon :: lat :: _) -> (
      match (Json.number lon, Json.number lat) with
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
      match Pack.all vertex vertices with
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
      match Pack.all raw_ring rings with
      | None -> None
      | Some (Dropped :: _) | Some [] -> Some Dropped
      | Some (Kept outer :: holes) ->
          Some
            (Kept
               (List.map
                  (Simplify.simplify ~tolerance_m:Pack.tolerance_m)
                  (outer :: List.filter_map kept holes))))
  | _ -> None

let geometry feature =
  match Json.member "geometry" feature with
  | None -> None
  | Some g -> (
      match (Json.member "type" g, Json.member "coordinates" g) with
      | Some (`String "MultiPolygon"), Some (`List polygons) ->
          Option.map (List.filter_map kept) (Pack.all polygon polygons)
      | Some (`String "Polygon"), Some coordinates ->
          Option.map (fun p -> Option.to_list (kept p)) (polygon coordinates)
      | _ -> None)

let commune feature =
  let props = properties feature in
  match (code_of props, name_of props, geometry feature) with
  | Some insee, Some name, Some (_ :: _ as polygons)
    when String.length insee = 5 ->
      Some ({insee; name; polygons} : Pack.commune)
  | _ -> None

let pack_of_payload ~departement json =
  match features json with
  | Error e -> Error e
  | Ok features -> (
      let returned = List.length features in
      match Json.member "numberMatched" json with
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
                ({
                   departement;
                   communes =
                     List.stable_sort
                       (fun (a : Pack.commune) b ->
                         String.compare a.insee b.insee)
                       communes;
                 }
                  : Pack.t)))
