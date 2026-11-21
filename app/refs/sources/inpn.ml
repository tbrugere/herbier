module Json = Herbier_net.Json
module Source = Herbier_domain.Reference.Source

let base = "https://odata-inpn.mnhn.fr"
let metropolitan_france = "TERFXFR"
let request path query = Request.make Source.Taxref ~base ~path ~query
let name ~cd_nom = request ["taxa"; "names"; string_of_int cd_nom] []

let status ~cd_ref =
  request
    ["taxa"; string_of_int cd_ref; "biogeographicStatuses"]
    [("locationId", metropolitan_france)]

let red_list ~cd_ref =
  request
    ["taxa"; "redLists"; "entries"]
    [
      ("taxrefId", string_of_int cd_ref);
      ("scopes", "NATIONAL");
      ("scopeLocationId", metropolitan_france);
    ]

let protections ~cd_ref =
  request
    ["taxa"; "protections"; "articles"]
    [
      ("taxrefIds", string_of_int cd_ref);
      ("embed", "SCOPE_LOCATION");
      ("size", "100");
    ]

type name = {taxref_id : int; valid : bool option; cd_ref : int}
[@@deriving eq, show]

(* The digits after the last "/taxa/" of a HAL href
   ("http://odata-inpn.mnhn.fr:443/taxa/117503{?embed}" gives 117503). *)
let taxon_id href =
  Option.bind (Decode.last_index ~sep:"/taxa/" href) (fun i ->
      let start = i + String.length "/taxa/" in
      let rec stop j =
        match j < String.length href with
        | true -> ( match href.[j] with '0' .. '9' -> stop (j + 1) | _ -> j)
        | false -> j
      in
      Json.digits (String.sub href start (stop start - start)))

let name_of_json json =
  let open Decode.Syntax in
  let* taxref_id = Decode.required_int "taxrefId" json in
  let valid = Decode.bool "valid" json in
  let href =
    Option.bind
      (Option.bind (Json.member "_links" json) (Json.member "taxon"))
      (Decode.string "href")
  in
  let+ cd_ref =
    match (Option.bind href taxon_id, valid) with
    | Some id, _ -> Ok id
    | None, Some false -> Decode.unexpected "/_links/taxon/href" "taxon id"
    | None, (Some true | None) -> Ok taxref_id
  in
  {taxref_id; valid; cd_ref}

(* The elements of [_embedded.<key>] that [element] reads. An empty page has
   no [_embedded]; [page.totalElements] tells it from a page whose shape
   changed. *)
let page key element = function
  | `Assoc _ as json -> (
      let open Decode.Syntax in
      let total =
        Option.bind (Json.member "page" json) (Decode.int "totalElements")
      in
      let* raw =
        match Json.member "_embedded" json with
        | None -> Ok []
        | Some embedded -> Decode.required_list ~at:"/_embedded" key embedded
      in
      match (List.filter_map element raw, total) with
      | [], Some n when n > 0 -> Decode.unexpected ("/_embedded/" ^ key) "array"
      | elements, (Some _ | None) -> Ok elements)
  | _ -> Decode.unexpected "" "object"

type status = {status : string; simplified : string option}
[@@deriving eq, show]

let status_of_json =
  page "biogeographicStatuses" (fun json ->
      Option.map
        (fun status ->
          {
            status;
            simplified = Decode.string "simplifiedBiogeographicStatus" json;
          })
        (Decode.string "biogeographicStatus" json))

type red_list_entry = {
  category : string;
  description : string option;
  trend : string option;
}
[@@deriving eq, show]

let red_list_of_json =
  page "redListEntries" (fun json ->
      Option.map
        (fun category ->
          {
            category;
            description = Decode.string "categoryDescription" json;
            trend = Decode.string "trend" json;
          })
        (Decode.string "category" json))

type location = {
  id : string option;
  name : string;
  level : string option;
  overseas : bool option;
}
[@@deriving eq, show]

type article = {
  scope : string;
  kind : string;
  category : string option;
  location : location option;
}
[@@deriving eq, show]

let location json =
  Option.map
    (fun name ->
      {
        id = Decode.string "locationId" json;
        name;
        level = Decode.string "level" json;
        overseas = Decode.bool "overseas" json;
      })
    (Decode.string "name" json)

let protections_of_json =
  page "protectionArticles" (fun json ->
      match (Decode.string "scope" json, Decode.string "type" json) with
      | Some scope, Some kind ->
          Some
            {
              scope;
              kind;
              category = Decode.string "category" json;
              location =
                Option.bind
                  (Option.bind
                     (Json.member "_embedded" json)
                     (Json.member "scopeLocation"))
                  location;
            }
      | None, _ | _, None -> None)
