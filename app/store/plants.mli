(** Queries on [plants] (architecture §2). Order of every list: [display_name]
    case-insensitively (ASCII, SQLite [collate nocase]), then [id]. This is the
    Collection grid's order (4a); a name starting with an accented capital sorts
    after "Z". *)

module Plant = Herbier_domain.Plant
module Plant_id = Herbier_domain.Ids.Plant_id
module Tag_id = Herbier_domain.Ids.Tag_id

val row : (Tables.Plants.t, Plant.t) Postgrest.Row.t
(** Decodes a [plants] row: any query that selects at least the plants columns
    under their own names, e.g. [select p.*] in a join. Use with [~json:[]]:
    [aliases] is parsed from its text here. A JSON array keeps its string
    elements in order and drops the others; any other JSON value, and text that
    is not JSON, is [[]] (lenient, never a decode error). *)

val query : string -> Codec.param list -> Plant.t Stmt.query
(** [query sql params] decodes each row with {!row}. *)

val order_by : string
(** ["display_name collate nocase, id"]: the order of every plant list. The
    columns are unqualified, so the query's [from] names [plants] alone. *)

val list : Plant.t Stmt.query
(** Every live plant. *)

val get : Plant_id.t -> Plant.t Stmt.query
(** The live plant with that id; 0 or 1 row. *)

val with_tag : Tag_id.t -> Plant.t Stmt.query
(** Live plants that have a live [plant_tags] row to this tag, the tag itself
    live; each plant once. *)

val upsert : Plant.t -> Stmt.t
(** Writes the whole record (see {!Stmt.upsert}): [deleted_at] included, so
    upserting a record with [deleted_at = None] revives the row. [aliases] is
    stored as a JSON array of strings (["[]"] when empty). *)

val soft_delete : Plant_id.t -> at:Ptime.t -> Stmt.t
(** Marks the plant deleted (see {!Stmt.soft_delete}). Its observations, photos
    and tag links are untouched. *)
