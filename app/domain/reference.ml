module Source = struct
  type t =
    | Gbif
    | Wikidata
    | Wikipedia
    | Powo
    | Ipni
    | Taxref
    | Tela
    | Eppo
    | Inat
    | Plantnet
  [@@deriving eq]

  let all =
    [Gbif; Wikidata; Wikipedia; Powo; Ipni; Taxref; Tela; Eppo; Inat; Plantnet]

  let to_string = function
    | Gbif -> "gbif"
    | Wikidata -> "wikidata"
    | Wikipedia -> "wikipedia"
    | Powo -> "powo"
    | Ipni -> "ipni"
    | Taxref -> "taxref"
    | Tela -> "tela"
    | Eppo -> "eppo"
    | Inat -> "inat"
    | Plantnet -> "plantnet"

  let of_string = function
    | "gbif" -> Some Gbif
    | "wikidata" -> Some Wikidata
    | "wikipedia" -> Some Wikipedia
    | "powo" -> Some Powo
    | "ipni" -> Some Ipni
    | "taxref" -> Some Taxref
    | "tela" -> Some Tela
    | "eppo" -> Some Eppo
    | "inat" -> Some Inat
    | "plantnet" -> Some Plantnet
    | _ -> None

  let to_json t = `String (to_string t)
  let of_json = function `String s -> of_string s | _ -> None
end

module Status = struct
  type t = Complete | Partial | Missing | Failed [@@deriving eq]

  let all = [Complete; Partial; Missing; Failed]

  let to_string = function
    | Complete -> "complete"
    | Partial -> "partial"
    | Missing -> "missing"
    | Failed -> "failed"

  let of_string = function
    | "complete" -> Some Complete
    | "partial" -> Some Partial
    | "missing" -> Some Missing
    | "failed" -> Some Failed
    | _ -> None

  let to_json t = `String (to_string t)
  let of_json = function `String s -> of_string s | _ -> None
end

module Organ = struct
  type t = Flower | Leaf | Fruit | Habit

  let all = [Flower; Leaf; Fruit; Habit]

  let to_string = function
    | Flower -> "flower"
    | Leaf -> "leaf"
    | Fruit -> "fruit"
    | Habit -> "habit"

  let of_string = function
    | "flower" -> Some Flower
    | "leaf" -> Some Leaf
    | "fruit" -> Some Fruit
    | "habit" -> Some Habit
    | _ -> None
end

type id = Ids.Reference_id.t [@@deriving eq]

let id_of_key ~plant ~source =
  Ids.Reference_id.of_key ~plant ~source:(Source.to_string source)

type t = {
  id : id;
  plant_id : Ids.Plant_id.t;
  source : Source.t;
  fetched_at : Ptime.t;
  payload : Yojson.Safe.t;
  status : Status.t;
  created_at : Ptime.t;
  updated_at : Ptime.t;
  deleted_at : Ptime.t option;
}
[@@deriving eq]

module Plant_ref = struct
  type id = Ids.Plant_ref_id.t [@@deriving eq]

  let id_of_key ~plant ~source =
    Ids.Plant_ref_id.of_key ~plant ~source:(Source.to_string source)

  type t = {
    id : id;
    plant_id : Ids.Plant_id.t;
    source : Source.t;
    external_id : string;
    url : string;
    created_at : Ptime.t;
    updated_at : Ptime.t;
    deleted_at : Ptime.t option;
  }
  [@@deriving eq]
end

module Image = struct
  type t = {
    plant_id : Ids.Plant_id.t;
    source : Source.t;
    organ : Organ.t;
    remote_url : string;
    licence : string;
    attribution : string;
    thumb_path : string option;
  }
end
