module Json = Herbier_net.Json
module Url = Herbier_net.Url
module Text = Herbier_domain.Text

let api = "https://my-api.plantnet.org/v2"
let automatic = "all"
let nb_results = 5

let identify_url ~key ~flora ~no_reject =
  String.concat ""
    [
      api;
      "/identify/";
      Url.encode flora;
      "?include-related-images=true&lang=fr&nb-results=";
      Int.to_string nb_results;
      (if no_reject then "&no-reject=true" else "");
      "&api-key=";
      Url.encode key;
    ]

let projects_url ~key = api ^ "/projects?lang=fr&api-key=" ^ Url.encode key
let asked_flora flora = Option.value (Text.non_blank flora) ~default:automatic

type 'image request = {
  flora : string;
  url : string;
  fields : (string * string) list;
  files : 'image Transport.file list;
}

type error =
  | No_key
  | No_photo
  | No_plant
  | Key_refused
  | Key_not_exposed
  | Quota_used_up
  | Refused_request of int
  | Unreachable of unreachable
  | Malformed of string

and unreachable = Timeout | Network | Server of int [@@deriving eq]

let error_to_string = function
  | No_key -> "no key"
  | No_photo -> "no photo"
  | No_plant -> "no plant"
  | Key_refused -> "key refused"
  | Key_not_exposed -> "key not exposed for the app"
  | Quota_used_up -> "quota used up"
  | Refused_request status -> Printf.sprintf "refused request (HTTP %d)" status
  | Unreachable Timeout -> "unreachable: timeout"
  | Unreachable Network -> "unreachable: network failure"
  | Unreachable (Server status) -> Printf.sprintf "unreachable: HTTP %d" status
  | Malformed what -> "malformed answer: " ^ what

let pp_error ppf e = Format.pp_print_string ppf (error_to_string e)

let identify_request ~key ~flora ~no_reject photos =
  match (Text.non_blank key, List.take Organ.max_photos photos) with
  | None, _ -> Error No_key
  | Some _, [] -> Error No_photo
  | Some key, photos ->
      let flora = asked_flora flora in
      Ok
        {
          flora;
          url = identify_url ~key ~flora ~no_reject;
          fields =
            List.map
              (fun (_, sent) -> ("organs", Organ.sent_to_string sent))
              photos;
          files =
            List.mapi
              (fun i (image, _) ->
                {
                  Transport.field = "images";
                  filename = Printf.sprintf "photo-%d.jpg" (i + 1);
                  image;
                })
              photos;
        }

let projects_request ~key =
  match Text.non_blank key with
  | None -> Error No_key
  | Some key -> Ok (projects_url ~key)

type image = {
  organ : Organ.t option;
  author : string;
  licence : string;
  citation : string option;
  small : string;
  medium : string;
}
[@@deriving eq]

let image_host = "bs.plantnet.org"
let image_prefix = "https://" ^ image_host ^ "/"
let on_image_host url = Url.under ~prefix:image_prefix url

type proposal = {
  score : float; [@equal Float.equal]
  name : string;
  author : string;
  scientific_name : string;
  family : string option;
  common_names : string list;
  gbif : int option;
  images : image list;
}
[@@deriving eq]

type answer = {
  proposals : proposal list;
  detected : Organ.t option list;
  flora : string option;
  remaining : int option;
}
[@@deriving eq]

let non_blank_member name json =
  Option.bind (Json.string_member name json) Text.non_blank

let hosted name json =
  match Json.string_member name json with
  | Some url when on_image_host url -> Some url
  | Some _ | None -> None

let image_of_json json =
  let open Option.Syntax in
  let* urls = Json.member "url" json in
  let* small = hosted "s" urls in
  let* medium = hosted "m" urls in
  let* author = non_blank_member "author" json in
  let+ licence = non_blank_member "license" json in
  {
    organ = Option.bind (Json.string_member "organ" json) Organ.of_string;
    author;
    licence;
    citation = non_blank_member "citation" json;
    small;
    medium;
  }

let list_member name json =
  match Json.member name json with Some (`List l) -> l | Some _ | None -> []

(* GBIF ids are sent as strings of digits; the OpenAPI types them as
   integers: both decode, anything else (or <= 0, or an overflow) is None. *)
let gbif_id = function
  | `String s when Json.is_digits s -> (
      match int_of_string_opt s with
      | Some n when n > 0 -> Some n
      | Some _ | None -> None)
  | `Int n when n > 0 -> Some n
  | _ -> None

let proposal_of_json json =
  let open Option.Syntax in
  let* score = Option.bind (Json.member "score" json) Json.number in
  let* species = Json.member "species" json in
  let+ name = non_blank_member "scientificNameWithoutAuthor" species in
  let author =
    Option.value
      (non_blank_member "scientificNameAuthorship" species)
      ~default:""
  in
  let scientific_name =
    match (non_blank_member "scientificName" species, author) with
    | Some full, _ -> full
    | None, "" -> name
    | None, author -> name ^ " " ^ author
  in
  {
    score;
    name;
    author;
    scientific_name;
    family =
      Option.bind
        (Json.member "family" species)
        (non_blank_member "scientificNameWithoutAuthor");
    common_names =
      List.filter_map
        (function `String s -> Text.non_blank s | _ -> None)
        (list_member "commonNames" species);
    gbif =
      Option.bind
        (Option.bind (Json.member "gbif" json) (Json.member "id"))
        gbif_id;
    images = List.filter_map image_of_json (list_member "images" json);
  }

let organ_of_prediction p =
  Option.bind (Json.string_member "organ" p) Organ.of_string

(* Pl@ntNet does not document the order of predictedOrgans: each element is
   matched to its photo by [image], the id [query.images] lists in the order
   the photos were sent. Two equal ids are the same picture, so taking the
   first element for both gives the same organ. *)
let detected json =
  let predictions = list_member "predictedOrgans" json in
  let prediction_of id =
    List.find_opt
      (fun p ->
        Option.equal String.equal (Json.string_member "image" p) (Some id))
      predictions
  in
  match Option.map (list_member "images") (Json.member "query" json) with
  | None | Some [] -> List.map organ_of_prediction predictions
  | Some ids ->
      List.map
        (function
          | `String id -> Option.bind (prediction_of id) organ_of_prediction
          | _ -> None)
        ids

let decode_answer body =
  match Json.parse body with
  | Error _ -> Error (Malformed "not JSON")
  | Ok json -> (
      match Json.member "results" json with
      | Some (`List results) -> (
          match (results, List.filter_map proposal_of_json results) with
          | _ :: _, [] -> Error (Malformed "results")
          | _, proposals ->
              Ok
                {
                  proposals;
                  detected = detected json;
                  flora = non_blank_member "preferedReferential" json;
                  remaining =
                    (match
                       Json.member "remainingIdentificationRequests" json
                     with
                    | Some (`Int n) -> Some n
                    | Some _ | None -> None);
                })
      | Some _ | None -> Error (Malformed "results"))

type project = {id : string; title : string} [@@deriving eq]

let project_of_json json =
  let open Option.Syntax in
  let* id = non_blank_member "id" json in
  let+ title = non_blank_member "title" json in
  {id; title}

let decode_projects body =
  match Json.parse body with
  | Error _ -> Error (Malformed "not JSON")
  | Ok (`List projects) -> Ok (List.filter_map project_of_json projects)
  | Ok _ -> Error (Malformed "projects")

type route = Identify | Projects

let origin_refused = "CORS error: Origin not allowed"

let is_origin_refused body =
  match Json.parse body with
  | Ok json ->
      Option.equal String.equal
        (non_blank_member "message" json)
        (Some origin_refused)
  | Error _ -> false

let error_of_answer ~route ~status ~body =
  match (status, route) with
  | 401, _ -> Key_refused
  | 403, _ when is_origin_refused body -> Key_not_exposed
  | 404, Identify -> No_plant
  | 429, _ -> Quota_used_up
  | status, _ when status >= 500 && status <= 599 -> Unreachable (Server status)
  | status, (Identify | Projects) -> Refused_request status

let error_of_failure : Transport.failure -> error = function
  | Timeout -> Unreachable Timeout
  | Network _ -> Unreachable Network
