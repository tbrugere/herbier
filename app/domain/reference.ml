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
  [@@deriving eq, show]

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

  include Lookup.Make (struct
    type nonrec t = t

    let all = all
    let to_string = to_string
  end)
end

module Status = struct
  type t = Complete | Partial | Missing | Failed [@@deriving eq, show]

  let all = [Complete; Partial; Missing; Failed]

  let to_string = function
    | Complete -> "complete"
    | Partial -> "partial"
    | Missing -> "missing"
    | Failed -> "failed"

  include Lookup.Make (struct
    type nonrec t = t

    let all = all
    let to_string = to_string
  end)
end

module Organ = struct
  type t = Flower | Leaf | Fruit | Habit [@@deriving eq, show]

  let all = [Flower; Leaf; Fruit; Habit]

  let to_string = function
    | Flower -> "flower"
    | Leaf -> "leaf"
    | Fruit -> "fruit"
    | Habit -> "habit"

  include Lookup.Make (struct
    type nonrec t = t

    let all = all
    let to_string = to_string
  end)
end

type id = Ids.Reference_id.t [@@deriving eq, show]

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
[@@deriving eq, show]

type reference = t

module Fetch_state = struct
  type t = {
    plant_id : Ids.Plant_id.t;
    source : Source.t;
    status : Status.t;
    fetched_at : Ptime.t;
  }
  [@@deriving eq, show]

  let of_reference (r : reference) =
    match r.deleted_at with
    | Some _ -> None
    | None ->
        Some
          {
            plant_id = r.plant_id;
            source = r.source;
            status = r.status;
            fetched_at = r.fetched_at;
          }
end

module Plant_ref = struct
  type id = Ids.Plant_ref_id.t [@@deriving eq, show]

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
  [@@deriving eq, show]
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
