(** The local [outbox] table (architecture §3, §4): one entry per change of a
    synced row, appended by {!Db.edit} in the same transaction as the change,
    pushed by the sync engine in [seq] order (architecture §4). Pure: statements
    as values, run by {!Db} on the device and by the sqlite3 CLI in test/store.
    {!Dev_seed} writes rows without entries ({!without_entry}). *)

type op =
  | Upsert
      (** Stored as ["upsert"]. Push always upserts the whole row on [id]
          ([on_conflict=id], architecture §4); a soft delete is an upsert
          carrying [deleted_at]. *)

type seq
(** An entry's position: [seq] of the table, increasing in append order among
    the entries present. [seq] has no [autoincrement], so once the newest entry
    is deleted the next append may reuse its number: a [seq] read before a
    {!delete} may name a different entry afterwards. *)

val seq_to_int : seq -> int

type entry = {
  seq : seq;
  table_name : string;  (** {!Postgrest.Col.name_of_table}, e.g. ["plants"]. *)
  row_id : string;  (** The row's [id], canonical lowercase UUID. *)
  op : op;
  payload : Yojson.Safe.t;
      (** The row as stored when the entry was appended, as the JSON object
          {!Postgrest.Input.to_json} gives for it: one PostgREST upsert body
          (all columns of [Tables], [null] for absent optional values). *)
  created_at : Ptime.t;
      (** Device clock (SQLite ['now']), millisecond precision. *)
  attempts : int;  (** Times {!park}ed. *)
  last_error : string option;  (** [Some] = parked. *)
}

type edit
(** One write to a synced table and how to build its entry: the statement, a
    query reading the written row back (by [id], or by natural key for
    [plant_tags]), and the row's encoding. *)

val edit :
  table:'table Postgrest.Col.table ->
  reread:'a Stmt.query ->
  row_id:('a -> string) ->
  input:('a -> ('table, [`Full]) Postgrest.Input.t) ->
  Stmt.t ->
  edit
(** [edit ~table ~reread ~row_id ~input stmt]. [reread] must return exactly one
    row once [stmt] has changed a row, whatever its [deleted_at]. Used by the
    per-table modules only. *)

val without_entry : edit -> Stmt.t
(** The write alone, with no entry. Run with {!Db.write}, it changes a synced
    row that is never pushed. Nothing in the types prevents that: by convention
    only {!Dev_seed} (and the pull, architecture §4) take this path, and
    {!Db.edit} runs it followed by the entry. *)

val reread : edit -> Stmt.t
(** The SQL and parameters of the read-back query. *)

val append : edit -> string -> (Stmt.t, Codec.error) result
(** [append e row] decodes [row] (one row of [reread e], as the plugin returns
    it: a JSON object text) with [reread e]'s decoder and gives
    [insert into outbox (table_name, row_id, op, payload_json, created_at)] with
    [table_name], [row_id] of the decoded value, ["upsert"],
    [Postgrest.Input.to_json (input v)] stored as JSON text, and the current UTC
    time as SQL computes it, in {!Codec.timestamp}'s 27-character format
    ([strftime('%Y-%m-%dT%H:%M:%f', 'now') || '000Z']); [attempts] 0,
    [last_error] null. [Error] when [row] does not decode (as {!Stmt.decode});
    never raises. *)

val next : limit:int -> entry Stmt.query
(** Entries not parked ([last_error] null), [seq] ascending, at most [limit]
    ([limit <= 0] → no row). [payload_json] is parsed as JSON; an entry whose
    [op] is not ["upsert"] or whose payload is not JSON is a decode error. *)

val count : int Stmt.query
(** Number of entries, parked ones included: one row. *)

val delete : seq -> Stmt.t
(** Removes the entry (after a 2xx push): 1 change, 0 if absent. *)

val park : seq -> error:string -> Stmt.t
(** Sets [last_error = error] and [attempts = attempts + 1] (after a 4xx): the
    entry leaves {!next}. 1 change, 0 if absent. *)
