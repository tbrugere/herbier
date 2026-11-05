(** The local SQLite database: open and migrate, statements with bound
    parameters, rows decoded with {!Postgrest.Row}. SQL is hand-written by the
    callers; no query DSL. {!run}, {!write} and {!write_all} run each statement
    in the plugin's own transaction; {!exec} runs its statements in one plugin
    transaction; {!edit} runs its statements in one explicit transaction.

    Every operation on a [t] ({!exec}, {!run}, {!query}, {!all}, {!find},
    {!write}, {!write_all}, {!edit}, {!user_version}, {!close}) starts only once
    the previous one on the same [t] has settled, success or error, so callers
    may start operations without awaiting each other: a statement arriving in
    the middle of an {!edit} would otherwise end its transaction. *)

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

val write_all : t -> Stmt.t list -> (unit, error) result Fut.t
(** {!write} each statement in order, stopping at the first error, which is
    returned. Not atomic: statements before the failing one stay applied. For
    the dev seed ({!Dev_seed.statements}), which appends no outbox entry. *)

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
    app writes a synced row; settings go through {!write}, the dev seed through
    {!write_all}. *)
