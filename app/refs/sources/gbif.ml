module Text = Herbier_domain.Text
module Json = Herbier_net.Json
module Organ = Herbier_domain.Reference.Organ

let backbone_dataset = "d7dddbf4-2cf0-4f39-9b2a-bb099caae36c"
let plantnet_dataset = "7a3679ef-5582-4aaa-81f0-8c2545cafc81"
let species_url key = "https://www.gbif.org/species/" ^ string_of_int key

(* Kingdom Plantae in the backbone (botanical-data-sources.md §1.1). *)
let plantae = "6"

let get path query =
  Request.make Herbier_domain.Reference.Source.Gbif
    ~base:"https://api.gbif.org/v1" ~path ~query

let species ~key = get ["species"; string_of_int key] []

(* A blank name matches the kingdom itself as EXACT. *)
let match_name ~name =
  match Decode.non_blank name with
  | None -> None
  | Some name ->
      Some (get ["species"; "match"] [("name", name); ("kingdom", "Plantae")])

let suggest ~q =
  get ["species"; "suggest"]
    [
      ("q", q);
      ("datasetKey", backbone_dataset);
      ("rank", "SPECIES");
      ("highertaxonKey", plantae);
      ("limit", "10");
    ]

let vernacular_search ~q =
  get ["species"; "search"]
    [
      ("q", q);
      ("datasetKey", backbone_dataset);
      ("highertaxonKey", plantae);
      ("qField", "VERNACULAR");
      ("limit", "20");
    ]

(* 1000 is GBIF's maximum page size: one page holds every row seen so far
   (186 vernacular names, 193 distributions for Digitalis). *)
let vernacular_names ~key =
  get ["species"; string_of_int key; "vernacularNames"] [("limit", "1000")]

let distributions ~key =
  get ["species"; string_of_int key; "distributions"] [("limit", "1000")]

let occurrence_count ~key =
  get ["occurrence"; "count"] [("taxonKey", string_of_int key)]

let plantnet_media ~key =
  get ["occurrence"; "search"]
    [
      ("datasetKey", plantnet_dataset);
      ("taxonKey", string_of_int key);
      ("mediaType", "StillImage");
      ("limit", "50");
    ]

module Status = struct
  type t = Accepted | Doubtful | Synonym | Other of string
  [@@deriving eq, show]

  let of_string = function
    | "ACCEPTED" -> Accepted
    | "DOUBTFUL" -> Doubtful
    | "SYNONYM" -> Synonym
    | s when String.ends_with ~suffix:"_SYNONYM" s -> Synonym
    | s -> Other s
end

module Taxon = struct
  type t = {
    key : int;
    scientific_name : string;
    canonical_name : string option;
    authorship : string option;
    rank : string option;
    status : Status.t option;
    accepted_key : int option;
    family : string option;
    vernacular_name : string option;
  }
  [@@deriving eq, show]

  let latin t = Option.value t.canonical_name ~default:t.scientific_name

  (* [/species/suggest] sends no [authorship]: it is what [scientificName]
     adds after the words of [canonicalName], which leaves out the hybrid sign
     and the rank markers ("Digitalis ×purpurascens Lindl.", "Digitalis
     purpurea subsp. purpurea"). *)
  let hybrid = "\u{00D7}"

  let marker = function
    | "x" | "subsp." | "ssp." | "var." | "subvar." | "f." | "fo." | "forma" ->
        true
    | token -> token = hybrid

  let same_word token word = token = word || token = hybrid ^ word

  let rec rest tokens words =
    match (tokens, words) with
    | _, [] -> Some tokens
    | [], _ :: _ -> None
    | token :: tokens', word :: words' -> (
        match same_word token word with
        | true -> rest tokens' words'
        | false -> (
            match marker token with true -> rest tokens' words | false -> None))

  let words s = List.filter (fun w -> w <> "") (String.split_on_char ' ' s)

  let authorship ~scientific_name ~canonical json =
    match (Decode.string "authorship" json, canonical) with
    | Some a, _ -> Some a
    | None, None -> None
    | None, Some c ->
        Option.bind
          (rest (words scientific_name) (words c))
          (fun tokens -> Decode.non_blank (String.concat " " tokens))

  let without_authorship t =
    Option.map
      (fun c ->
        let tokens = words t.scientific_name in
        match rest tokens (words c) with
        | Some after ->
            String.concat " "
              (List.take (List.length tokens - List.length after) tokens)
        | None -> c)
      t.canonical_name

  (* The endpoints name the same fields differently: [key]/[usageKey],
     [taxonomicStatus]/[status], [acceptedKey]/[acceptedUsageKey]. *)
  let of_json ~at ~key ~status ~accepted json =
    let open Decode.Syntax in
    let* k = Decode.required_int ~at key json in
    let+ scientific_name = Decode.required_string ~at "scientificName" json in
    let canonical_name = Decode.string "canonicalName" json in
    {
      key = k;
      scientific_name;
      canonical_name;
      authorship = authorship ~scientific_name ~canonical:canonical_name json;
      rank = Decode.string "rank" json;
      status = Option.map Status.of_string (Decode.string status json);
      accepted_key = Decode.int accepted json;
      family = Decode.string "family" json;
      vernacular_name = Decode.string "vernacularName" json;
    }

  let of_species ~at =
    of_json ~at ~key:"key" ~status:"taxonomicStatus" ~accepted:"acceptedKey"
end

type 'a page = {
  results : 'a list;
  dropped : Decode.error list;
  end_of_records : bool;
  count : int option;
}
[@@deriving eq, show]

(* Elements are decoded with their index in the pointer; one that fails is
   dropped (style §8.4) and its error kept. *)
let elements ~at f items =
  let decoded =
    List.mapi (fun i item -> f ~at:(Printf.sprintf "%s/%d" at i) item) items
  in
  ( List.filter_map Result.to_option decoded,
    List.filter_map (function Ok _ -> None | Error e -> Some e) decoded )

let envelope json (results, dropped) =
  {
    results;
    dropped;
    end_of_records =
      Option.value ~default:false (Decode.bool "endOfRecords" json);
    count = Decode.int "count" json;
  }

let page f json =
  let open Decode.Syntax in
  let+ items = Decode.required_list "results" json in
  envelope json (elements ~at:"/results" f items)

let species_of_json json = Taxon.of_species ~at:"" json

type match_ =
  | No_match
  | Higher_rank of Taxon.t
  | Matched of {taxon : Taxon.t; fuzzy : bool; confidence : int option}
[@@deriving eq, show]

let match_of_json json =
  let open Decode.Syntax in
  let taxon () =
    Taxon.of_json ~at:"" ~key:"usageKey" ~status:"status"
      ~accepted:"acceptedUsageKey" json
  in
  let matched ~fuzzy =
    let+ taxon = taxon () in
    Matched {taxon; fuzzy; confidence = Decode.int "confidence" json}
  in
  match Decode.string "matchType" json with
  | Some "NONE" -> Ok No_match
  | Some "HIGHERRANK" ->
      let+ taxon = taxon () in
      Higher_rank taxon
  | Some "EXACT" -> matched ~fuzzy:false
  | Some "FUZZY" -> matched ~fuzzy:true
  | Some _ | None ->
      Decode.unexpected "/matchType" "EXACT|FUZZY|HIGHERRANK|NONE"

let suggest_of_json = function
  | `List items ->
      Ok
        (fst
           (elements ~at:""
              (fun ~at ->
                Taxon.of_json ~at ~key:"key" ~status:"status"
                  ~accepted:"acceptedKey")
              items))
  | _ -> Decode.unexpected "" "array"

module Vernacular = struct
  type t = {
    name : string;
    language : string option;
    source : string option;
    country : string option;
  }
  [@@deriving eq, show]

  let of_json ~at json =
    let open Decode.Syntax in
    let+ name = Decode.required_string ~at "vernacularName" json in
    {
      name;
      language = Decode.string "language" json;
      source = Decode.string "source" json;
      country = Decode.string "country" json;
    }
end

let vernacular_search_of_json =
  page (fun ~at json ->
      let open Decode.Syntax in
      let+ taxon = Taxon.of_species ~at json in
      ( taxon,
        fst
          (elements ~at:(at ^ "/vernacularNames") Vernacular.of_json
             (Decode.list "vernacularNames" json)) ))

let vernacular_names_of_json = page Vernacular.of_json

module Distribution = struct
  type t = {
    location_id : string option;
    locality : string option;
    country : string option;
    status : string option;
    establishment_means : string option;
    threat_status : string option;
    source : string option;
  }
  [@@deriving eq, show]

  let of_json ~at json =
    let location_id = Decode.string "locationId" json in
    let locality = Decode.string "locality" json in
    let country = Decode.string "country" json in
    match (location_id, locality, country) with
    | None, None, None ->
        Decode.unexpected (at ^ "/locationId") "locationId|locality|country"
    | _ ->
        Ok
          {
            location_id;
            locality;
            country;
            status = Decode.string "status" json;
            establishment_means = Decode.string "establishmentMeans" json;
            threat_status = Decode.string "threatStatus" json;
            source = Decode.string "source" json;
          }
end

let distributions_of_json = page Distribution.of_json

let occurrence_count_of_json = function
  | `Int n when n >= 0 -> Ok n
  | _ -> Decode.unexpected "" "non-negative int"

module Image = struct
  type t = {
    occurrence_key : string;
    url : string;
    organ : Organ.t option;
    organ_label : string option;
    licence : string;
    attribution : string;
    observation_url : string option;
  }
  [@@deriving eq, show]
end

(* Under js_of_ocaml Yojson gives [`Intlit] for keys above 2^31. *)
let occurrence_key json =
  match Json.member "key" json with
  | Some (`Int k) when k >= 0 -> Some (string_of_int k)
  | Some (`Intlit s) when Json.is_digits s -> Some s
  | _ -> None

let after_last ~sep s =
  Option.map
    (fun i ->
      let start = i + String.length sep in
      String.sub s start (String.length s - start))
    (Decode.last_index ~sep s)

(* "Iris Selcho (cc-by-sa)": the holder, then the licence code. The holder
   may be missing: "(cc-by)". *)
let split_license license =
  let s = String.trim license in
  let n = String.length s in
  match (n > 0 && s.[n - 1] = ')', String.rindex_opt s '(') with
  | true, Some i ->
      let code = String.lowercase_ascii (String.sub s (i + 1) (n - i - 2)) in
      let code =
        match String.starts_with ~prefix:"cc" code with
        | true -> Some code
        | false -> None
      in
      (code, Text.non_blank (String.sub s 0 i))
  | _ -> (None, None)

let image ~key ~references json =
  let license = Decode.string "license" json in
  let licence, holder =
    match license with Some l -> split_license l | None -> (None, None)
  in
  let attribution =
    match Decode.string "rightsHolder" json with
    | Some _ as a -> a
    | None -> (
        match Decode.string "creator" json with
        | Some _ as a -> a
        | None -> holder)
  in
  let url =
    match Decode.string "identifier" json with
    | Some u when String.starts_with ~prefix:"https://" u -> Some u
    | _ -> None
  in
  match (Decode.string "type" json, url, licence, attribution) with
  | Some "StillImage", Some url, Some licence, Some attribution ->
      let organ_label =
        Option.bind (Decode.string "title" json) (fun title ->
            Option.bind (after_last ~sep:": " title) (fun w ->
                Text.non_blank (String.lowercase_ascii w)))
      in
      Some
        {
          Image.occurrence_key = key;
          url;
          organ = Option.bind organ_label Organ.of_string;
          organ_label;
          licence;
          attribution;
          observation_url =
            (match Decode.string "source" json with
            | Some _ as s -> s
            | None -> references);
        }
  | _ -> None

let plantnet_media_of_json json =
  let open Decode.Syntax in
  let+ occurrences = Decode.required_list "results" json in
  let keyed, dropped =
    elements ~at:"/results"
      (fun ~at occurrence ->
        match occurrence_key occurrence with
        | None -> Decode.unexpected (at ^ "/key") "non-negative int"
        | Some key -> Ok (key, occurrence))
      occurrences
  in
  envelope json
    ( List.concat_map
        (fun (key, occurrence) ->
          let references = Decode.string "references" occurrence in
          List.filter_map (image ~key ~references)
            (Decode.list "media" occurrence))
        keyed,
      dropped )
