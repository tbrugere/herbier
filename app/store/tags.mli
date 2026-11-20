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

val links : Tag.Plant_tag.t Stmt.query
(** Every live link between a live tag and a live plant, by [tag_id] then
    [plant_id]: the tag filters of 4a and 4c and the counts of 4l, in one query.
*)

val input : Tag.t -> (Tables.Tags.t, [`Full]) Postgrest.Input.t
(** Every column of [Tables.Tags], in its declaration order. The upsert's
    columns and the outbox payload. *)

val plant_tag_input :
  Tag.Plant_tag.t -> (Tables.Plant_tags.t, [`Full]) Postgrest.Input.t
(** Every column of [Tables.Plant_tags], in its declaration order: the outbox
    payload of {!tag} and {!untag}. *)

val upsert : Tag.t -> Outbox.edit
(** Writes the whole record ({!Stmt.upsert} of {!input}); always changes the
    row, so {!Herbier_store_io.Db.edit} appends one entry. Read back by [id]. *)

val soft_delete : Tag_id.t -> at:Ptime.t -> Outbox.edit
(** {!Stmt.soft_delete}; read back by [id] whatever [deleted_at]. Appends an
    entry when the tag was live, nothing otherwise. Links to the tag are left as
    they are; queries ignore links to a deleted tag. *)

val upsert_plant_tag : Tag.Plant_tag.t -> Outbox.bare
(** Writes a whole [plant_tags] row with conflict target [(plant_id, tag_id)],
    the natural key. On conflict it sets [updated_at] and [deleted_at] from the
    record and keeps the existing row's [id] and [created_at]. The pull's and
    the dev seed's write (architecture §4), inside [Db.bare_transaction]: no
    outbox entry. *)

val tag : plant:Plant_id.t -> tag:Tag_id.t -> at:Ptime.t -> Outbox.edit
(** Puts the tag on the plant (architecture §2 revive rule):
    - no row for [(plant, tag)]: inserts one with
      [id = Ids.Plant_tag_id.of_key ~plant ~tag], [created_at = updated_at = at]
      and [deleted_at = null] → appends an entry (payload id the derived one);
    - a soft-deleted row: revives it ([deleted_at = null], [updated_at = at]; id
      and created_at kept) → appends an entry carrying the stored id;
    - a live row: nothing changes ([updated_at] not bumped) → appends nothing.

    The conflict target is [(plant_id, tag_id)]; the row is read back by that
    pair. Foreign keys apply: an unknown plant or tag makes
    {!Herbier_store_io.Db.edit} fail. *)

val untag : plant:Plant_id.t -> tag:Tag_id.t -> at:Ptime.t -> Outbox.edit
(** Soft-deletes the live link ([deleted_at = updated_at = at]) → appends an
    entry (payload [deleted_at = at], stored id); appends nothing when there is
    no live link. Read back by [(plant_id, tag_id)]. *)
