module Property = struct
  type t = Gbif_key | Powo | Inat

  let to_string = function
    | Gbif_key -> "P846"
    | Powo -> "P5037"
    | Inat -> "P3151"
end

let get query =
  Request.make Herbier_domain.Reference.Source.Wikidata
    ~base:"https://www.wikidata.org/w/api.php" ~path:[]
    ~query:(query @ [("format", "json"); ("origin", "*")])

let is_space = function ' ' | '\t' | '\n' | '\r' | '\012' -> true | _ -> false

let search ~property ~value =
  match value = "" || String.exists (fun c -> c = '"' || is_space c) value with
  | true -> None
  | false ->
      Some
        (get
           [
             ("action", "query");
             ("list", "search");
             ( "srsearch",
               Printf.sprintf "haswbstatement:\"%s=%s\""
                 (Property.to_string property)
                 value );
           ])

(* The wikis whose sitelinks are kept, in the order of the result. *)
let wikis = ["fr"; "en"; "de"; "it"]

let entity qid =
  get
    [
      ("action", "wbgetentities");
      ("ids", Qid.to_string qid);
      ("props", "claims|sitelinks");
      ( "sitefilter",
        String.concat "|" (List.map (fun lang -> lang ^ "wiki") wikis) );
    ]

let api_error json =
  match Decode.member "error" json with
  | None -> None
  | Some error -> (
      match Decode.string "code" error with
      | Some code ->
          Some
            (Decode.Api_error
               {
                 code;
                 info = Option.value ~default:"" (Decode.string "info" error);
               })
      | None ->
          Some
            (Decode.Unexpected
               {path = "/error"; expected = "object with a string code"}))

let search_of_json json =
  match api_error json with
  | Some e -> Error e
  | None -> (
      match
        Option.bind (Decode.member "query" json) (Decode.member "search")
      with
      | Some (`List hits) ->
          Ok
            (List.filter_map
               (fun hit ->
                 Option.bind (Decode.string "title" hit) Qid.of_string)
               hits)
      | _ -> Decode.unexpected "/query/search" "array")

module Entity = struct
  type name = {lang : string; text : string}
  type sitelink = {lang : string; title : string}

  type t = {
    qid : Qid.t;
    gbif_key : int option;
    powo : string option;
    ipni : string option;
    taxref : int option;
    tela : int option;
    eppo : string option;
    inat : int option;
    common_names : name list;
    sitelinks : sitelink list;
  }
end

type rank = Preferred | Normal

(* The statements of [property] ranked preferred or normal and with a value,
   in order. *)
let statements property claims =
  List.filter_map
    (fun statement ->
      let rank =
        match Decode.string "rank" statement with
        | Some "preferred" -> Some Preferred
        | Some "normal" -> Some Normal
        | _ -> None
      in
      let snak = Decode.member "mainsnak" statement in
      let value =
        match Option.bind snak (Decode.string "snaktype") with
        | Some "value" ->
            Option.bind
              (Option.bind snak (Decode.member "datavalue"))
              (Decode.member "value")
        | _ -> None
      in
      match (rank, value) with
      | Some rank, Some value -> Some (rank, value)
      | _ -> None)
    (Decode.list property claims)

let string_value = function `String s -> Decode.non_blank s | _ -> None

(* A single-valued external id: the first preferred statement, else the
   first normal one. *)
let single property claims =
  let preferred, normal =
    List.partition
      (function Preferred, _ -> true | Normal, _ -> false)
      (statements property claims)
  in
  let first values = List.find_map (fun (_, v) -> string_value v) values in
  match first preferred with Some _ as v -> v | None -> first normal

let numeric property claims =
  Option.bind (single property claims) (fun s ->
      match Decode.is_digits s with
      | true -> int_of_string_opt s
      | false -> None)

let common_names claims =
  List.filter_map
    (fun (_, value) ->
      match (Decode.string "language" value, Decode.string "text" value) with
      | Some lang, Some text -> Some {Entity.lang; text}
      | _ -> None)
    (statements "P1843" claims)

let sitelinks json =
  let links = Option.value ~default:`Null (Decode.member "sitelinks" json) in
  List.filter_map
    (fun lang ->
      Option.bind
        (Decode.member (lang ^ "wiki") links)
        (fun link ->
          Option.map
            (fun title -> {Entity.lang; title})
            (Decode.string "title" link)))
    wikis

let entity_of_json json =
  match api_error json with
  | Some e -> Error e
  | None -> (
      match Decode.member "entities" json with
      | Some (`Assoc ((key, entity) :: _)) -> (
          match Decode.member "missing" entity with
          | Some _ -> Ok None
          | None -> (
              match Option.bind (Decode.string "id" entity) Qid.of_string with
              | None -> Decode.unexpected ("/entities/" ^ key ^ "/id") "Q-id"
              | Some qid ->
                  let claims =
                    Option.value ~default:`Null (Decode.member "claims" entity)
                  in
                  Ok
                    (Some
                       {
                         Entity.qid;
                         gbif_key = numeric (Property.to_string Gbif_key) claims;
                         powo = single (Property.to_string Powo) claims;
                         ipni = single "P961" claims;
                         taxref = numeric "P3186" claims;
                         tela = numeric "P3105" claims;
                         eppo = single "P3031" claims;
                         inat = numeric (Property.to_string Inat) claims;
                         common_names = common_names claims;
                         sitelinks = sitelinks entity;
                       })))
      | _ -> Decode.unexpected "/entities" "object with one entity")
