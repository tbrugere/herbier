(** The local [sync_state] table (architecture §3): per synced table, the server
    [updated_at] of the newest row a pull applied. Local-only; columns declared
    here. Pure: statements as values. Timestamps in {!Codec.timestamp}'s format
    (microseconds kept). *)

val all : (string * Ptime.t) Stmt.query
(** Every cursor [(table_name, last_pulled_at)], by [table_name]. A
    [last_pulled_at] that does not parse is a decode error (the whole query
    fails, as [Db.all]). *)

val set : table_name:string -> Ptime.t -> Stmt.t
(** [insert … on conflict (table_name) do update set last_pulled_at =
     excluded.last_pulled_at]: 1 change. *)

val reset : Stmt.t
(** [delete from sync_state]: the next pull reads every table from the start
    (#dev/sync « Curseurs à zéro »). *)
