(** User tags and their assignment to plants. *)

type id = Ids.Tag_id.t
(** The id of the tag: [Ids.Tag_id.t] under a local name. *)

type t = {
  id : id;
  name : string;
  created_at : Ptime.t;
  updated_at : Ptime.t;
  deleted_at : Ptime.t option;  (** [Some] = soft-deleted. *)
}

val equal : t -> t -> bool
(** Field by field: [Ptime.equal] on instants (no truncation). *)

val pp : Format.formatter -> t -> unit

(** Row of [plant_tags]: one tag on one plant. Soft-deleted when the tag is
    removed so the removal syncs; at most one row per [(plant_id, tag_id)], and
    re-adding a removed tag revives its row. *)
module Plant_tag : sig
  type id = Ids.Plant_tag_id.t
  (** The id of the link row: [Ids.Plant_tag_id.t] under a local name. *)

  type t = {
    id : id;
    plant_id : Ids.Plant_id.t;
    tag_id : Ids.Tag_id.t;
    created_at : Ptime.t;
    updated_at : Ptime.t;
    deleted_at : Ptime.t option;  (** [Some] = soft-deleted. *)
  }

  val equal : t -> t -> bool
  (** Field by field: [Ptime.equal] on instants (no truncation). *)

  val pp : Format.formatter -> t -> unit
end
