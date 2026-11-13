(** Statements as values: SQL text with its bound parameters, and for a query
    how each result row decodes. Pure: built by the per-table modules, run by
    {!Herbier_store_io.Db} on the device and by the sqlite3 CLI in test/store.
    SQL uses positional [?] parameters only (no [?NNN], no named ones) and never
    has a [?] inside a string literal, so a test may inline [params] by
    position. *)

(* style: transparent, not private, because a statement with its own where
   clause ([Tags.tag], [References.put]) is written as a record and test/store
   reads [sql] and [params] to inline them. *)
type t = {sql : string; params : Codec.param list}
(** One statement; [List.length params] is the number of [?] in [sql]. *)

type 'a query
(** A [SELECT] and the decoder of one of its rows into ['a]. *)

val query :
  json:'table Codec.json_column list ->
  ('table, 'a) Postgrest.Row.t ->
  string ->
  Codec.param list ->
  'a query
(** [query ~json row sql params]. [json] as in {!Codec.decode}. *)

val stmt : 'a query -> t
(** The SQL and parameters of the query. *)

val decode : 'a query -> string -> ('a, Codec.error) result
(** [decode q text] is [Codec.decode ~json row text] for the [json] and [row] of
    [q]: one row as the plugin returns it (a JSON object text). Never raises. *)

val by_ids :
  json:'table Codec.json_column list ->
  table:'table Postgrest.Col.table ->
  ('table, 'a) Postgrest.Row.t ->
  string list ->
  'a query
(** [by_ids ~json ~table row ids] is [select * from table where id in (?, …)],
    one text parameter per id (the canonical lowercase id), any [deleted_at],
    rows in no particular order. The caller keeps [ids] at most {!max_ids} long.
    [[]] → [where id in ()], no row. *)

val max_ids : int
(** 500: the most ids one {!by_ids} takes, below SQLite's 999-parameter floor.
*)

val upsert :
  ?conflict:string list ->
  ?keep:string list ->
  table:'table Postgrest.Col.table ->
  ('table, [`Full]) Postgrest.Input.t ->
  t
(** [upsert ~conflict ~keep ~table input] is
    [insert into table (c1, …) values (?, …) on conflict (<conflict>) do update
     set c = excluded.c] over the fields of [input] in order, each bound with
    [Codec.param] of its column (an [Optional] field holding [Unspecified],
    which the type admits, is left out, as {!Postgrest.Input.to_json} does).
    Every column but the [conflict] and [keep] ones is in the update
    ([do nothing] when none is left). [input] must include the [conflict]
    columns. It never deletes the old row, so foreign-key cascades never fire
    (see {!Schema}). [upsert] and {!soft_delete} are shared so that every synced
    table follows the one write convention.

    [~conflict] (default [["id"]]) is the conflict target, a unique key of the
    table, given as the columns' [name]s from {!Tables}; [~keep] (default [[]])
    names more columns the update leaves as stored. *)

val soft_delete :
  table:'table Postgrest.Col.table -> id:Codec.param -> at:Ptime.t -> t
(** [update table set deleted_at = at, updated_at = at where id = id and
     deleted_at is null]: 1 change when the row was live, 0 when it is absent or
    already deleted (its first [deleted_at] is kept). *)

(** One column of a natural key and its value, written as {!Codec.param}. *)
type 'table key_column =
  | Is : ('table, 'a, 'optional) Postgrest.Col.t * 'a -> 'table key_column

val soft_delete_by :
  table:'table Postgrest.Col.table ->
  key:'table key_column * 'table key_column list ->
  at:Ptime.t ->
  t
(** {!soft_delete} by another key: [where c1 = v1 and … and deleted_at is null]
    over [key]'s columns and values, in order (a natural key: [plant_tags]'
    plant and tag, [reference]'s plant and source). *)
