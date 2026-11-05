(** Binding to [@capacitor-community/sqlite] through its [SQLiteConnection]
    wrapper ([globalThis.herbier.sqlite]). Read-write, unencrypted connections
    only. SQL is passed through untouched; no schema, no logic. *)

type t
(** A connection to one database (an [SQLiteDBConnection]). *)

(** A bound parameter. [Int] is an OCaml int (32-bit under jsoo); larger
    integers (epoch milliseconds) go as [Float]. No blob, no bool: SQLite has no
    bool and the app stores no blobs. *)
type value = Null | Int of int | Float of float | Text of string

type changes = {changed : int; last_id : int option}
(** Result of {!run}: rows changed, and the plugin's [lastId]. [lastId] is the
    connection's [last_insert_rowid()], so it is meaningful only right after an
    [INSERT] (after an [UPDATE] or [DELETE] it is a stale rowid of an earlier
    insert). [None] when the plugin omits it or it is outside the [int] range.
*)

val connect : database:string -> (t, Cap_error.t) result Fut.t
(** [connect ~database] returns a connection to [database] (a bare name such as
    ["herbier"]; the plugin stores [<database>SQLite.db]). Safe to call again
    after a WebView reload (reuses the native connection). Its consistency check
    closes native connections the JS side does not track, so call it once per
    database per page load. The database is not opened: call {!open_}. *)

val open_ : t -> (unit, Cap_error.t) result Fut.t
(** Opens the database file, creating it if absent. *)

val close : t -> (unit, Cap_error.t) result Fut.t
(** Closes the database, then the connection
    ([closeConnection(database, false)]). The connection is closed even when
    closing the database fails; the first error is returned. [t] must not be
    used afterwards; a new {!connect} is needed. *)

val execute : t -> string -> (int, Cap_error.t) result Fut.t
(** [execute db sql] runs one statement without parameters, in the plugin's own
    transaction (its default [transaction = true]); returns [changes.changes].
    The plugin rewrites [sql] before running it (splits it on [";"] and newline,
    drops what follows [--] on each line, even inside a string literal, joins
    lines, turns [end;] into [END;]), so [sql] holds no [--] and no string
    literal, and several statements (or a trigger) go through {!execute_set}
    instead. [sql] carries no data: values go through {!run} or {!query}
    parameters. [Error (Unexpected "changes.changes")] if the plugin omits it.
*)

val execute_set : t -> string list -> (int, Cap_error.t) result Fut.t
(** [execute_set db statements] runs [statements] in order, without parameters,
    in one plugin transaction ([executeSet(set, true)], each set element
    [{statement; values = []}]): all of them apply or none. The plugin prepares
    each string as given, with no splitting, so each one is exactly one
    statement (multi-line, comments and trigger bodies allowed); Android's
    statement compiler ignores any text after the first statement. Returns
    [changes.changes], a [total_changes()] difference over the whole set.
    [Error (Rejected _)] for an empty list (the plugin refuses an empty set) or
    when a statement fails (the transaction is then rolled back);
    [Error (Unexpected "changes.changes")] if the plugin omits it. *)

val run :
  ?transaction:bool ->
  t ->
  string ->
  value list ->
  (changes, Cap_error.t) result Fut.t
(** [run db sql params] runs one statement with positional [?] parameters.
    [transaction] (default [true], the plugin's default) is the plugin's third
    argument: [true] wraps the statement in the plugin's own transaction;
    [~transaction:false] runs it in the caller's explicit transaction
    ({!begin_transaction}). [changed] is [changes.changes] (required, else
    [Unexpected "changes.changes"]), a [total_changes()] difference: it includes
    rows changed by triggers. [last_id] as described in {!changes}. *)

val begin_transaction : t -> (unit, Cap_error.t) result Fut.t
(** [beginTransaction()]. [Error] when a transaction is already active on the
    connection or the database is not open. Statements run inside must pass
    [~transaction:false] to {!run}: with the plugin's own per-call transaction
    they fail, and their failure ends the open transaction (rolled back).
    {!execute} and {!execute_set} always use the plugin's own transaction, so
    inside one they fail the same way and roll the open transaction back. *)

val commit_transaction : t -> (unit, Cap_error.t) result Fut.t
(** [commitTransaction()]. [Error] when no transaction is active or the commit
    fails; either way no transaction is active afterwards. *)

val rollback_transaction : t -> (unit, Cap_error.t) result Fut.t
(** [rollbackTransaction()]: ends the active transaction without committing;
    does nothing (and is [Ok ()]) when none is active. *)

val query : t -> string -> value list -> (string list, Cap_error.t) result Fut.t
(** [query db sql params] runs a [SELECT] and returns its rows in order, each as
    the JSON text of the object the plugin returns ([{"column": value, …}],
    [JSON.stringify] of each element of [values]). SQLite NULL is JSON [null].
    [Error (Unexpected "values")] when the result has no [values] array or a row
    cannot be stringified. *)
