(** Queries on [tags] and [plant_tags]. Order of tag lists: [name] with
    [collate nocase], then [id]. *)

module Tag = Herbier_domain.Tag
module Tag_id = Herbier_domain.Ids.Tag_id
module Plant_id = Herbier_domain.Ids.Plant_id

val row : (Tables.Tags.t, Tag.t) Postgrest.Row.t
val plant_tag_row : (Tables.Plant_tags.t, Tag.Plant_tag.t) Postgrest.Row.t

val list : Tag.t Stmt.query
(** Every live tag (4l, the chips of 4a). *)

val get : Tag_id.t -> Tag.t Stmt.query
(** The live tag with that id; 0 or 1 row. *)

val of_plant : Plant_id.t -> Tag.t Stmt.query
(** Live tags with a live link to the plant. *)

val upsert : Tag.t -> Stmt.t
(** Writes the whole record (see {!Stmt.upsert}). *)

val soft_delete : Tag_id.t -> at:Ptime.t -> Stmt.t
(** See {!Stmt.soft_delete}. Links to the tag are left as they are; queries
    ignore links to a deleted tag. *)

val upsert_plant_tag : Tag.Plant_tag.t -> Stmt.t
(** Writes a whole [plant_tags] row with conflict target [(plant_id, tag_id)],
    the natural key. On conflict it sets [updated_at] and [deleted_at] from the
    record and keeps the existing row's [id] and [created_at]. *)

val tag : plant:Plant_id.t -> tag:Tag_id.t -> at:Ptime.t -> Stmt.t
(** Puts the tag on the plant (architecture §2 revive rule):
    - no row for [(plant, tag)]: inserts one with
      [id = Ids.Plant_tag_id.of_key ~plant ~tag], [created_at = updated_at = at]
      and [deleted_at = null] → 1 change;
    - a soft-deleted row: revives it ([deleted_at = null], [updated_at = at]; id
      and created_at kept) → 1 change;
    - a live row: nothing changes (0 changes, [updated_at] not bumped).

    The conflict target is [(plant_id, tag_id)]. Foreign keys apply: an unknown
    plant or tag makes [Db.write] fail. *)

val untag : plant:Plant_id.t -> tag:Tag_id.t -> at:Ptime.t -> Stmt.t
(** Soft-deletes the live link ([deleted_at = updated_at = at]) → 1 change; 0
    when there is no live link. *)
