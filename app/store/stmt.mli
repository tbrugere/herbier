(** Statements as values: SQL text with its bound parameters, and for a query
    how each result row decodes. Pure: built by the per-table modules, run by
    {!Db} on the device and by the sqlite3 CLI in test/store. SQL uses
    positional [?] parameters only (no [?NNN], no named ones) and never has a
    [?] inside a string literal, so a test may inline [params] by position. *)

(* style: transparent, not private, because a statement with its own conflict
   target ([Tags.tag], [Settings.set]) is written as a record and test/store
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

val col : ('table, 'a, 'optional) Postgrest.Col.t -> 'a -> string * Codec.param
(** [col c v] is [(c.name, Codec.param c v)], one column of {!upsert}. *)

val upsert :
  table:'table Postgrest.Col.table -> (string * Codec.param) list -> t
(** [upsert ~table columns] is
    [insert into table (c1, …) values (?, …) on conflict (id) do update set c =
     excluded.c] for every column but ["id"], with the parameters of [columns]
    in order ([do nothing] when ["id"] is the only column). [columns] must
    include ["id"]. It never deletes the old row, so foreign-key cascades never
    fire (see {!Schema}). [upsert] and {!soft_delete} are shared so that every
    synced table follows the one write convention. *)

val soft_delete :
  table:'table Postgrest.Col.table -> id:Codec.param -> at:Ptime.t -> t
(** [update table set deleted_at = at, updated_at = at where id = id and
     deleted_at is null]: 1 change when the row was live, 0 when it is absent or
    already deleted (its first [deleted_at] is kept). *)
