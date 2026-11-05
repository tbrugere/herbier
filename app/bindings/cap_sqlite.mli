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
(** [execute db sql] runs one or more [;]-separated statements without
    parameters (DDL, migrations), in the plugin's own transaction (its default
    [transaction = true]); returns [changes.changes]. [sql] carries no data:
    values go through {!run} or {!query} parameters.
    [Error (Unexpected "changes.changes")] if the plugin omits it. *)

val run : t -> string -> value list -> (changes, Cap_error.t) result Fut.t
(** [run db sql params] runs one statement with positional [?] parameters, in
    the plugin's own transaction. [changed] is [changes.changes] (required, else
    [Unexpected "changes.changes"]); [last_id] as described in {!changes}. *)

val query : t -> string -> value list -> (string list, Cap_error.t) result Fut.t
(** [query db sql params] runs a [SELECT] and returns its rows in order, each as
    the JSON text of the object the plugin returns ([{"column": value, …}],
    [JSON.stringify] of each element of [values]). SQLite NULL is JSON [null].
    [Error (Unexpected "values")] when the result has no [values] array or a row
    cannot be stringified. *)
