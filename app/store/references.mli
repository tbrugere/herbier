(** Queries and edits on [reference] (one row per source of a plant) and
    [plant_refs] (the plant's id at each source), architecture §2, §4. New rows
    get the id derived from [(plant_id, source)]; writes conflict on that
    natural key and keep the stored [id] and [created_at]; every install derives
    the same id from the key (architecture §4). Lists are ordered by [source]
    label ascending. *)

module Reference = Herbier_domain.Reference
module Plant_id = Herbier_domain.Ids.Plant_id

val row : (Tables.Reference.t, Reference.t) Postgrest.Row.t
(** Decode with {!json}: [payload] is JSON text in SQLite. *)

val json : Tables.Reference.t Codec.json_column list
(** [[Codec.json Tables.Reference.payload]]: the [~json] of every query decoding
    {!row}. *)

val plant_ref_row : (Tables.Plant_refs.t, Reference.Plant_ref.t) Postgrest.Row.t
(** Decode with [~json:[]]. *)

val input : Reference.t -> (Tables.Reference.t, [`Full]) Postgrest.Input.t
(** Every column of [Tables.Reference], in its declaration order: the outbox
    payload of {!put}. *)

val plant_ref_input :
  Reference.Plant_ref.t -> (Tables.Plant_refs.t, [`Full]) Postgrest.Input.t
(** Every column of [Tables.Plant_refs], in its declaration order: the outbox
    payload of {!link} and {!unlink}. *)

val of_plant : Plant_id.t -> Reference.t Stmt.query
(** Live rows of the plant. *)

val get : Plant_id.t -> Reference.Source.t -> Reference.t Stmt.query
(** The live row for [(plant, source)]; 0 or 1 row. *)

val put :
  plant:Plant_id.t ->
  source:Reference.Source.t ->
  fetched_at:Ptime.t ->
  payload:Yojson.Safe.t ->
  status:Reference.Status.t ->
  at:Ptime.t ->
  Outbox.edit
(** Stores what the source said:
    - no row: inserts [id = Reference.id_of_key ~plant ~source],
      [created_at = updated_at = at], [deleted_at = null];
    - a row (live or soft-deleted): sets [fetched_at], [payload], [status],
      [updated_at = at], [deleted_at = null]; keeps [id] and [created_at].

    Always changes the row, so {!Herbier_store_io.Db.edit} appends one entry
    carrying the stored id. Read back by [(plant_id, source)]. [payload] must be
    a JSON object ([Herbier_refs.Payload]'s builders always give one): a [`Null]
    would be stored as the text ["null"], which {!row} cannot read back. An
    unknown plant makes {!Herbier_store_io.Db.edit} fail (foreign key). *)

val remove :
  plant:Plant_id.t -> source:Reference.Source.t -> at:Ptime.t -> Outbox.edit
(** Soft-deletes the live reference row of [(plant, source)]
    ([deleted_at = updated_at = at]) → one entry carrying the stored id; nothing
    (no entry) when there is none or it is already deleted. Read back by
    [(plant_id, source)]. A later {!put} revives it. Used when a plant is linked
    to another taxon: the old taxon's rows must not survive as kept rows of the
    new one. *)

val upsert_row : Reference.t -> Outbox.bare
(** The whole row, conflict target [(plant_id, source)]: no row → inserted with
    the record's [id] and [created_at]; a row (live or deleted) → every other
    column set from the record ([fetched_at], [payload] as JSON text, [status],
    [updated_at], [deleted_at]), its [id] and [created_at] kept. Never deletes
    (no replace). The pull's write of [reference], inside [Db.bare_transaction]:
    no outbox entry. *)

val upsert_plant_ref : Reference.Plant_ref.t -> Outbox.bare
(** Same rule for [plant_refs] ([external_id], [url], [updated_at], [deleted_at]
    set; [id], [created_at] kept). *)

val plant_refs : Plant_id.t -> Reference.Plant_ref.t Stmt.query
(** Live plant refs of the plant. *)

val link :
  plant:Plant_id.t ->
  source:Reference.Source.t ->
  external_id:string ->
  url:string ->
  at:Ptime.t ->
  Outbox.edit
(** Sets the plant's id at [source] (revive rule as {!Tags.tag}):
    - no row: inserts one with
      [id = Reference.Plant_ref.id_of_key ~plant ~source],
      [created_at = updated_at = at] → one entry;
    - a soft-deleted row: revives it with the new [external_id] and [url],
      [updated_at = at] → one entry carrying the stored id;
    - a live row with another [external_id] or [url]: sets both and [updated_at]
      → one entry;
    - a live row with the same [external_id] and [url]: nothing changes → no
      entry.

    Read back by [(plant_id, source)]. An unknown plant makes
    {!Herbier_store_io.Db.edit} fail. *)

val unlink :
  plant:Plant_id.t -> source:Reference.Source.t -> at:Ptime.t -> Outbox.edit
(** Soft-deletes the live plant ref ([deleted_at = updated_at = at]) → one
    entry; nothing when there is none. Read back by [(plant_id, source)]. *)
