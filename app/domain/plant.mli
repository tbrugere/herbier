(** A plant of the collection (architecture §2). [scientific_name = None] is a
    free-name plant, valid on its own. *)

type id = Ids.Plant_id.t
(** The id of the plant: [Ids.Plant_id.t] under a local name. *)

type t = {
  id : id;
  display_name : string;
  aliases : string list;  (** In display order; may be empty. *)
  scientific_name : string option;
  authorship : string option;
  gbif_key : int option;  (** GBIF usageKey (32-bit on GBIF's side). *)
  notes : string;  (** [""] when there are none. *)
  notes_updated_at : Ptime.t option;
      (** [None] until notes are first edited. *)
  cover_photo_id : Ids.Photo_id.t option;
  created_at : Ptime.t;
  updated_at : Ptime.t;
  deleted_at : Ptime.t option;  (** [Some] = soft-deleted. *)
}

val equal : t -> t -> bool
(** Field by field: [Ptime.equal] on instants (no truncation), [aliases] in
    order. *)

val v : id:id -> at:Ptime.t -> string -> t
(** A free-name plant of that display name, created and updated [at], with no
    alias, notes or cover. *)
