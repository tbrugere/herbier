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
    | Plantuse

  val equal : t -> t -> bool
  val pp : Format.formatter -> t -> unit

  val all : t list
  (** Every constructor, in declaration order. *)

  val to_string : t -> string
  (** ["gbif"], ["wikidata"], ["wikipedia"], ["powo"], ["ipni"], ["taxref"],
      ["tela"], ["eppo"], ["inat"], ["plantnet"], ["plantuse"]: the values of
      its Postgres lookup table. *)

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

  val equal : t -> t -> bool
  val pp : Format.formatter -> t -> unit

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

  val equal : t -> t -> bool
  val pp : Format.formatter -> t -> unit

  val all : t list
  (** Every constructor, in declaration order. *)

  val to_string : t -> string
  (** ["flower"] | ["leaf"] | ["fruit"] | ["habit"] (Pl@ntNet's organ names). *)

  val of_string : string -> t option
  (** Exact inverse of [to_string]; [None] for any other string. *)
end

type id = Ids.Reference_id.t
(** The id of the reference row: [Ids.Reference_id.t] under a local name. *)

val id_of_key : plant:Ids.Plant_id.t -> source:Source.t -> id
(** [Ids.Reference_id.of_key ~plant ~source:(Source.to_string source)]: the id
    every install derives for the row of [(plant, source)]. *)

type t = {
  id : id;
  plant_id : Ids.Plant_id.t;
  source : Source.t;
  fetched_at : Ptime.t;
  payload : Yojson.Safe.t;
      (** A JSON object, one member per call made to the source (architecture
          §6). Never [`Null]. *)
  status : Status.t;
  created_at : Ptime.t;
  updated_at : Ptime.t;
  deleted_at : Ptime.t option;  (** [Some] = soft-deleted. *)
}
(** Row of [reference]: what one source said about the plant. At most one row
    per [(plant_id, source)]. *)

val equal : t -> t -> bool
(** Field by field, [Ptime.equal] on instants (no truncation); [payload] by
    [Yojson.Safe.equal]: object key order ignored, as [jsonb] reorders keys, and
    [`Int 1] differs from [`Float 1.]. *)

val pp : Format.formatter -> t -> unit

type reference := t

(** What the fetch rules read of a live row of [reference]: no payload, so a
    pass over every plant does not parse every source's answer. *)
module Fetch_state : sig
  type t = {
    plant_id : Ids.Plant_id.t;
    source : Source.t;
    status : Status.t;
    fetched_at : Ptime.t;
  }

  val equal : t -> t -> bool
  val pp : Format.formatter -> t -> unit

  val of_reference : reference -> t option
  (** The row's state; [None] for a soft-deleted row. *)
end

(** Row of [plant_refs]: the plant's identifier at one source. At most one row
    per [(plant_id, source)]. *)
module Plant_ref : sig
  type id = Ids.Plant_ref_id.t
  (** The id of the link row: [Ids.Plant_ref_id.t] under a local name. *)

  val id_of_key : plant:Ids.Plant_id.t -> source:Source.t -> id
  (** [Ids.Plant_ref_id.of_key ~plant ~source:(Source.to_string source)]. *)

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

  val equal : t -> t -> bool
  (** Field by field: [Ptime.equal] on instants (no truncation). *)

  val pp : Format.formatter -> t -> unit
end

(** A reference image (handoff 4f organ photos). Device-local row: not synced.
    One row per [(plant_id, source, organ)]. *)
module Image : sig
  type t = {
    plant_id : Ids.Plant_id.t;
    source : Source.t;
    organ : Organ.t;
    remote_url : string;
    licence : string;
    attribution : string;
    thumb_path : string option;
        (** ~300 px under [refthumbs/]; [None] until downloaded or after «
            Libérer ». *)
  }
end
