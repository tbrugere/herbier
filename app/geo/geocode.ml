module Places = Herbier_domain.Places
module Text = Herbier_domain.Text
module Json = Herbier_net.Json
module Url = Herbier_net.Url

type provider = Photon | Geoplateforme [@@deriving eq]

let provider_to_string = function
  | Photon -> "photon"
  | Geoplateforme -> "geoplateforme"

type request = {provider : provider; url : string} [@@deriving eq]

let request_to_string {provider; url} = provider_to_string provider ^ " " ^ url

let request_endpoint {provider; url} =
  let base =
    match String.index_opt url '?' with
    | Some i -> String.sub url 0 i
    | None -> url
  in
  provider_to_string provider ^ " " ^ base

let coordinate = Printf.sprintf "%.5f"

let make provider base query =
  let query =
    String.concat "&"
      (List.map (fun (k, v) -> Url.encode k ^ "=" ^ Url.encode v) query)
  in
  {provider; url = base ^ "?" ^ query}

let photon_reverse ({lat; lon} : Places.point) =
  make Photon "https://photon.komoot.io/reverse"
    [
      ("lat", coordinate lat);
      ("lon", coordinate lon);
      ("lang", "fr");
      ("limit", "1");
      ("layer", "city");
      ("layer", "district");
      ("layer", "locality");
    ]

let photon_search ?near ?(limit = 8) q =
  let bias =
    match near with
    | None -> []
    | Some ({lat; lon} : Places.point) ->
        [("lat", coordinate lat); ("lon", coordinate lon)]
  in
  make Photon "https://photon.komoot.io/api"
    ([
       ("q", q);
       ("lang", "fr");
       ("limit", string_of_int (Int.max 1 (Int.min 20 limit)));
     ]
    @ bias)

let geoplateforme ~category ~searchgeom ({lat; lon} : Places.point) =
  make Geoplateforme "https://data.geopf.fr/geocodage/reverse"
    [
      ("index", "poi");
      ("lon", coordinate lon);
      ("lat", coordinate lat);
      ("limit", "1");
      ("category", category);
      ("searchgeom", searchgeom);
    ]

(* The API answers 400 to a larger circle. *)
let geoplateforme_max_radius_m = 500.

let geoplateforme_lieu_dit ({lat; lon} as p : Places.point) =
  geoplateforme ~category:"lieu-dit habité,lieu-dit non habité"
    ~searchgeom:
      (Printf.sprintf {|{"type":"Circle","coordinates":[%s,%s],"radius":%d}|}
         (coordinate lon) (coordinate lat)
         (Float.to_int (Float.min Places.radius_m geoplateforme_max_radius_m)))
    p

let geoplateforme_commune ({lat; lon} as p : Places.point) =
  geoplateforme ~category:"commune"
    ~searchgeom:
      (Printf.sprintf {|{"type":"Point","coordinates":[%s,%s]}|}
         (coordinate lon) (coordinate lat))
    p

let geoplateforme_wfs query =
  make Geoplateforme "https://data.geopf.fr/wfs/ows" query

(* Comparisons with nan are false, so a nan coordinate is outside. *)
let in_france ({lat; lon} : Places.point) =
  41.3 <= lat && lat <= 51.2 && -5.5 <= lon && lon <= 9.7

type error =
  | Not_json of string
  | Unexpected of {path : string; expected : string}
[@@deriving eq]

let error_to_string = function
  | Not_json msg -> "not JSON: " ^ msg
  | Unexpected {path; expected} ->
      Printf.sprintf "unexpected payload at %S: expected %s" path expected

let transient_status status =
  Int.equal status 429 || (500 <= status && status <= 599)

let json_of_string s = Result.map_error (fun m -> Not_json m) (Json.parse s)

(* A longer value from a provider is not a place name; it would be synced
   as is. *)
let max_value_bytes = 200

let non_blank s =
  Option.bind (Text.non_blank s) (fun s ->
      match String.length s > max_value_bytes with
      | true -> None
      | false -> Some s)

let string name json =
  match Json.member name json with Some (`String s) -> non_blank s | _ -> None

let properties feature =
  Option.value (Json.member "properties" feature) ~default:(`Assoc [])

let features json =
  match Json.member "features" json with
  | Some (`List l) -> Ok l
  | _ -> Error (Unexpected {path = "/features"; expected = "array"})

let first_properties json =
  Result.map
    (function [] -> None | feature :: _ -> Some (properties feature))
    (features json)

let photon_place_values =
  [
    "city";
    "town";
    "village";
    "hamlet";
    "isolated_dwelling";
    "farm";
    "suburb";
    "quarter";
    "neighbourhood";
    "borough";
    "locality";
    "island";
    "islet";
  ]

let photon_name json =
  Result.map
    (fun props ->
      Option.bind props (fun props ->
          let place =
            match (string "osm_key" props, string "osm_value" props) with
            | Some "place", Some value when List.mem value photon_place_values
              ->
                string "name" props
            | _ -> None
          in
          List.find_map Fun.id
            [place; string "district" props; string "city" props]))
    (first_properties json)

let geoplateforme_name json =
  Result.map
    (fun props ->
      Option.bind props (fun props ->
          match string "toponym" props with
          | Some name -> Some name
          | None -> (
              match Json.member "name" props with
              | Some (`List names) ->
                  List.find_map
                    (function `String s -> non_blank s | _ -> None)
                    names
              | _ -> None)))
    (first_properties json)

type place = {name : string; context : string option; point : Places.point}
[@@deriving eq]

let point feature : Places.point option =
  match
    Option.bind (Json.member "geometry" feature) (Json.member "coordinates")
  with
  | Some (`List (lon :: lat :: _)) -> (
      match (Json.number lon, Json.number lat) with
      | Some lon, Some lat -> Some {lat; lon}
      | _ -> None)
  | _ -> None

let context props name =
  let parts =
    List.fold_left
      (fun acc key ->
        match string key props with
        | Some s when not (String.equal s name || List.mem s acc) -> s :: acc
        | Some _ | None -> acc)
      []
      ["city"; "county"; "country"]
  in
  match parts with
  | [] -> None
  | parts -> Some (String.concat ", " (List.rev parts))

let photon_place feature =
  let props = properties feature in
  match (string "name" props, point feature) with
  | Some name, Some point -> Some {name; context = context props name; point}
  | _ -> None

let photon_places json =
  Result.map (List.filter_map photon_place) (features json)

type 'a program = Done of 'a | Get of request * (Yojson.Safe.t -> 'a program)

let step request decode next =
  Get
    ( request,
      fun json ->
        match Result.map (fun n -> Option.bind n Near.phrase) (decode json) with
        | Error e -> Done (Error e)
        | Ok (Some phrase) -> Done (Ok (Some phrase))
        | Ok None -> next () )

let rec map f = function
  | Done x -> Done (f x)
  | Get (request, k) -> Get (request, fun json -> map f (k json))

let rec or_else p next =
  match p with
  | Done (Ok None) -> next ()
  | Done (Ok (Some _) | Error _) -> p
  | Get (request, k) -> Get (request, fun json -> or_else (k json) next)

let none () = Done (Ok None)
let reverse_photon p = step (photon_reverse p) photon_name none

let reverse_ign p =
  match in_france p with
  | false -> none ()
  | true ->
      step (geoplateforme_lieu_dit p) geoplateforme_name (fun () ->
          step (geoplateforme_commune p) geoplateforme_name none)
