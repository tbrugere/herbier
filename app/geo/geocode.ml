module Places = Herbier_domain.Places

type provider = Photon | Geoplateforme

let provider_to_string = function
  | Photon -> "photon"
  | Geoplateforme -> "geoplateforme"

type request = {provider : provider; url : string}

let equal_provider a b =
  match (a, b) with
  | Photon, Photon | Geoplateforme, Geoplateforme -> true
  | (Photon | Geoplateforme), _ -> false

let equal_request a b =
  equal_provider a.provider b.provider && String.equal a.url b.url

let request_to_string {provider; url} = provider_to_string provider ^ " " ^ url

let request_endpoint {provider; url} =
  let base =
    match String.index_opt url '?' with
    | Some i -> String.sub url 0 i
    | None -> url
  in
  provider_to_string provider ^ " " ^ base

(* style: [unreserved] and [encode] are Herbier_refs.Request's: geo does not
   depend on refs (layout.md, known copies). *)
let unreserved = function
  | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '-' | '.' | '_' | '~' -> true
  | _ -> false

let encode s =
  let buf = Buffer.create (String.length s * 3) in
  String.iter
    (fun c ->
      match unreserved c with
      | true -> Buffer.add_char buf c
      | false -> Buffer.add_string buf (Printf.sprintf "%%%02X" (Char.code c)))
    s;
  Buffer.contents buf

let coordinate = Printf.sprintf "%.5f"

let make provider base query =
  let query =
    String.concat "&" (List.map (fun (k, v) -> encode k ^ "=" ^ encode v) query)
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

let apostrophe = "’"

(* The contracted article and the rest of the name, when [name] starts with
   an article (ASCII, case-insensitive) followed by its separator. *)
let article name =
  let lower = String.lowercase_ascii name in
  let after prefix =
    match String.starts_with ~prefix lower with
    | false -> None
    | true -> (
        let len = String.length prefix in
        match String.trim (String.sub name len (String.length name - len)) with
        | "" -> None
        | rest -> Some rest)
  in
  List.find_map
    (fun (prefix, contracted) ->
      Option.map (fun rest -> contracted ^ rest) (after prefix))
    [
      ("le ", "Près du ");
      ("les ", "Près des ");
      ("la ", "Près de la ");
      ("l'", "Près de l" ^ apostrophe);
      ("l" ^ apostrophe, "Près de l" ^ apostrophe);
    ]

let vowels =
  String.split_on_char ' '
    "A E I O U Y a e i o u y À Â Ä É È Ê Ë Î Ï Ô Ö Ù Û Ü Œ Æ à â ä é è ê ë î ï \
     ô ö ù û ü œ æ"

let near name =
  match String.trim name with
  | "" -> None
  | name -> (
      match article name with
      | Some phrase -> Some phrase
      | None -> (
          match
            List.exists (fun prefix -> String.starts_with ~prefix name) vowels
          with
          | true -> Some ("Près d" ^ apostrophe ^ name)
          | false -> Some ("Près de " ^ name)))

type error =
  | Not_json of string
  | Unexpected of {path : string; expected : string}

let error_to_string = function
  | Not_json msg -> "not JSON: " ^ msg
  | Unexpected {path; expected} ->
      Printf.sprintf "unexpected payload at %S: expected %s" path expected

let equal_error a b =
  match (a, b) with
  | Not_json a, Not_json b -> String.equal a b
  | Unexpected a, Unexpected b ->
      String.equal a.path b.path && String.equal a.expected b.expected
  | (Not_json _ | Unexpected _), _ -> false

let json_of_string s =
  match Yojson.Safe.from_string s with
  | json -> Ok json
  (* Under js_of_ocaml a deeply nested body raises Failure (a JS stack
     overflow) rather than Json_error: any exception degrades to Not_json. *)
  | exception Yojson.Json_error msg -> Error (Not_json msg)
  | exception e -> Error (Not_json (Printexc.to_string e))

let member name = function
  | `Assoc fields -> (
      match List.assoc_opt name fields with
      | None | Some `Null -> None
      | Some v -> Some v)
  | _ -> None

(* A longer value from a provider is not a place name; it would be synced
   as is. *)
let max_value_bytes = 200

let non_blank s =
  match String.trim s with
  | "" -> None
  | s when String.length s > max_value_bytes -> None
  | s -> Some s

let string name json =
  match member name json with Some (`String s) -> non_blank s | _ -> None

let properties feature =
  Option.value (member "properties" feature) ~default:(`Assoc [])

let features json =
  match member "features" json with
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
              match member "name" props with
              | Some (`List names) ->
                  List.find_map
                    (function `String s -> non_blank s | _ -> None)
                    names
              | _ -> None)))
    (first_properties json)

type place = {name : string; context : string option; point : Places.point}

let equal_place a b =
  String.equal a.name b.name
  && Option.equal String.equal a.context b.context
  && Places.equal_point a.point b.point

let number = function
  | `Int i -> Some (Float.of_int i)
  | `Float f when Float.is_finite f -> Some f
  | _ -> None

let point feature : Places.point option =
  match Option.bind (member "geometry" feature) (member "coordinates") with
  | Some (`List (lon :: lat :: _)) -> (
      match (number lon, number lat) with
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
        match Result.map (fun n -> Option.bind n near) (decode json) with
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
