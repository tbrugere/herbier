(** Reference data about a plant, one row per external source (architecture §2,
    §6), plus the plant's links to external taxa and the organ images. *)

module Source : sig
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

  val all : t list
  (** Every constructor, in declaration order. *)

  val to_string : t -> string
  (** ["gbif"], ["wikidata"], ["wikipedia"], ["powo"], ["ipni"], ["taxref"],
      ["tela"], ["eppo"], ["inat"], ["plantnet"]: the values of its Postgres
      lookup table. *)

  val of_string : string -> t option
  (** Exact inverse of [to_string]; [None] for any other string. *)

  val to_json : t -> Yojson.Safe.t
  (** The JSON string [to_string t]: the column value as PostgREST sends and
      receives it. *)

  val of_json : Yojson.Safe.t -> t option
  (** [of_string] of a JSON string; [None] for any other JSON value. *)
end

module Status : sig
  type t = Complete | Partial | Missing | Failed

  val all : t list
  (** Every constructor, in declaration order. *)

  val to_string : t -> string
  (** ["complete"] | ["partial"] | ["missing"] | ["failed"]: the values of its
      Postgres lookup table. *)

  val of_string : string -> t option
  (** Exact inverse of [to_string]; [None] for any other string. *)

  val to_json : t -> Yojson.Safe.t
  (** The JSON string [to_string t]: the column value as PostgREST sends and
      receives it. *)

  val of_json : Yojson.Safe.t -> t option
  (** [of_string] of a JSON string; [None] for any other JSON value. *)
end

module Organ : sig
  type t = Flower | Leaf | Fruit | Habit

  val all : t list
  (** Every constructor, in declaration order. *)

  val to_string : t -> string
  (** ["flower"] | ["leaf"] | ["fruit"] | ["habit"] (Pl@ntNet's organ names). *)

  val of_string : string -> t option
  (** Exact inverse of [to_string]; [None] for any other string. *)
end

type id = Ids.Reference_id.t
(** The id of the reference row: [Ids.Reference_id.t] under a local name. *)

type t = {
  id : id;
  plant_id : Ids.Plant_id.t;
  source : Source.t;
  fetched_at : Ptime.t;
  payload : string;
      (** JSON text as returned, lightly normalised; parsed in [refs/]. *)
  status : Status.t;
  created_at : Ptime.t;
  updated_at : Ptime.t;
  deleted_at : Ptime.t option;  (** [Some] = soft-deleted. *)
}
(** Row of [reference]: what one source said about the plant. At most one row
    per [(plant_id, source)]. *)

(** Row of [plant_refs]: the plant's identifier at one source. At most one row
    per [(plant_id, source)]. *)
module Plant_ref : sig
  type id = Ids.Plant_ref_id.t
  (** The id of the link row: [Ids.Plant_ref_id.t] under a local name. *)

  type t = {
    id : id;
    plant_id : Ids.Plant_id.t;
    source : Source.t;
    external_id : string;
        (** The source's own id, as text (GBIF key, Q-id, cd_nom…). *)
    url : string;
    created_at : Ptime.t;
    updated_at : Ptime.t;
    deleted_at : Ptime.t option;  (** [Some] = soft-deleted. *)
  }
end

(** A reference image (handoff 4f organ photos). Device-local row: not synced.
*)
module Image : sig
  type t = {
    plant_id : Ids.Plant_id.t;
    source : Source.t;
    organ : Organ.t option;
    remote_url : string;
    licence : string;
    attribution : string;
    thumb_path : string option;
        (** ~300 px under [refthumbs/]; [None] until downloaded or after «
            Libérer ». *)
  }
end
