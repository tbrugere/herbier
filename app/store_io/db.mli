(** The local SQLite database: open and migrate, statements with bound
    parameters, rows decoded with {!Postgrest.Row}. SQL is hand-written by the
    callers; no query DSL. {!run} and {!write} run each statement in the
    plugin's own transaction; {!exec} runs its statements in one plugin
    transaction; {!edit} and {!bare_transaction} run their statements in one
    explicit transaction.

    Every operation on a [t] ({!exec}, {!run}, {!query}, {!all}, {!find},
    {!write}, {!edit}, {!bare_transaction}, {!user_version}, {!close}) starts
    only once the previous one on the same [t] has settled, success or error, so
    callers may start operations without awaiting each other: a statement
    arriving in the middle of an {!edit} would otherwise end its transaction. *)

module Codec := Herbier_store.Codec
module Schema := Herbier_store.Schema
module Stmt := Herbier_store.Stmt
module Outbox := Herbier_store.Outbox

type t

type error =
  | Plugin of Herbier_bindings.Cap_error.t  (** A plugin call failed. *)
  | Decode of {sql : string; row : int; error : Codec.error}
      (** Row [row] (0-based) of [sql]'s result did not decode. *)
  | Schema of Schema.error
      (** The file's [user_version] is unknown to this app; nothing applied. *)
  | Migration of {version : int; error : Herbier_bindings.Cap_error.t}
      (** Migration [version] failed and was rolled back; earlier ones stay. *)
  | Not_migrated of {expected : int; found : int}
      (** After migrating, [user_version] reads [found], not [expected]. *)
  | Unexpected_rows of {sql : string; count : int}
      (** [sql] returned [count] rows where one row (or at most one, for
          {!find}) was expected. *)
  | Foreign_key of {table : string; parent : string; count : int}
      (** {!bare_transaction}: [count] rows break a deferred foreign key; the
          first one is in [table] and points at [parent]. *)
  | Raised of string
      (** An OCaml exception escaped while starting the operation (a bug);
          [Printexc.to_string] of it. Later operations still run. *)

val error_to_string : error -> string

val open_ : database:string -> (t, error) result Fut.t
(** [open_ ~database] connects ([Cap_sqlite.connect], so: at most one open [t]
    per database at a time; after {!close}, [open_] again), opens (creating the
    file if absent), reads [user_version], applies {!Schema.pending} one
    migration per [executeSet] of {!Schema.batch} (one transaction each), then
    reads [user_version] again and requires {!Schema.latest}. A fresh file and
    an existing file at version 0 take the same path; a file already at
    {!Schema.latest} runs no statement besides the two reads. On any error after
    connecting, the connection is closed (its own close error is dropped) and
    the first error is returned. *)

val close : t -> (unit, error) result Fut.t
(** Closes the database and its connection; [t] is unusable afterwards. *)

val user_version : t -> (int, error) result Fut.t
(** [PRAGMA user_version]. *)

val exec : t -> string list -> (unit, error) result Fut.t
(** [exec db statements] runs [statements] in order without parameters,
    atomically (one plugin transaction, [Cap_sqlite.execute_set]); each string
    is exactly one statement. They carry no data: values go through {!run} or
    {!query}. An empty list is a [Plugin] error. *)

val run : t -> string -> Codec.param list -> (int, error) result Fut.t
(** [run db sql params] runs one statement with positional [?] parameters;
    returns the plugin's count of rows changed, which includes rows changed by
    triggers. *)

val query :
  t ->
  json:'table Codec.json_column list ->
  ('table, 'a) Postgrest.Row.t ->
  string ->
  Codec.param list ->
  ('a list, error) result Fut.t
(** [query db ~json spec sql params] runs a [SELECT] and decodes every row in
    order with [Codec.decode ~json spec]. The first row that fails gives
    [Decode]; no partial list. [json] names the result columns holding JSON text
    ([[]] when none). *)

val all : t -> 'a Stmt.query -> ('a list, error) result Fut.t
(** Runs the query; every row decoded with {!Stmt.decode}, in order. First
    failing row → [Decode {sql; row; error}]; no partial list. *)

val find : t -> 'a Stmt.query -> ('a option, error) result Fut.t
(** For queries that return at most one row ([get], [Settings.get]): [Ok None]
    for no row, [Ok (Some v)] for one, [Error (Unexpected_rows {sql; count})]
    for more. *)

val write : t -> Stmt.t -> (int, error) result Fut.t
(** {!run} of the statement: rows changed (triggers included, as {!run}). For
    local-only tables ({!Settings}); a synced row is written with {!edit}. A
    constraint violation (foreign key, unique, check) is a [Plugin] error like
    any other; only its message tells them apart. *)

val edit : t -> Outbox.edit list -> (int, error) result Fut.t
(** [edit db edits] runs every edit and its entry in one transaction, in order:
    for each edit, its statement; when it changed at least one row, its
    {!Outbox.reread}, then the {!Outbox.append} statement for that row. Commits
    and returns the number of entries appended, or rolls everything back and
    returns the first error:
    - [Plugin _]: a statement failed (constraint, foreign key, …), or the begin
      or commit failed;
    - [Unexpected_rows {sql; count}]: the read-back returned [count <> 1] rows;
    - [Decode {sql; row = 0; error}]: the read-back row did not decode.

    [edits = []] is [Ok 0] and touches nothing. A rollback failure is logged to
    the console; the first error is the one returned. This is the only way the
    app's screens write a synced row; settings go through {!write}, the pull and
    the dev seed through {!bare_transaction}. *)

type tx
(** An open bare transaction; valid only inside the callback of
    {!bare_transaction}. *)

val bare_transaction :
  t -> (tx -> ('a, error) result Fut.t) -> ('a, error) result Fut.t
(** Queued like every operation. [beginTransaction];
    [pragma defer_foreign_keys = on] (foreign keys checked at the end, so rows
    can be written children before parents; SQLite resets the pragma at commit
    or rollback); [f tx]; [pragma foreign_key_check]; commit. [f]'s [Error], an
    OCaml exception raised starting [f] ([Raised]), a foreign-key violation
    ([Foreign_key], found before the commit: on Android a failed commit cannot
    be rolled back and leaves the connection unusable) or a failed commit
    ([Plugin _]) → rollback, the first error returned; a failed rollback is
    logged as in {!edit}. Appends no outbox entry. [f] must use only {!Tx} on
    [tx]: any other operation on [t] queues behind this one and never starts
    (deadlock). For the pull and the dev seed. An exception raised later, inside
    a continuation of [f]'s future, is not caught: the future never settles, so
    the transaction stays open and every later operation on [t] waits forever
    ([edit]'s chain has the same limit). [f] must therefore be total. *)

module Tx : sig
  val all : tx -> 'a Stmt.query -> ('a list, error) result Fut.t
  (** As {!all}, inside the transaction (sees its writes). *)

  val write : tx -> Outbox.bare -> (int, error) result Fut.t
  (** Rows changed. A constraint error other than a deferred foreign key fails
      here ([Plugin _]). *)

  val write_local : tx -> Stmt.t -> (int, error) result Fut.t
  (** A local-only table ([Sync_state.set]). *)
end
