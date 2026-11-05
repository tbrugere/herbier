(** The local SQLite database: open and migrate, statements with bound
    parameters, rows decoded with {!Postgrest.Row}. SQL is hand-written by the
    callers; no query DSL. {!exec} and {!run} each run in the plugin's own
    transaction; there is no multi-statement transaction with parameters. *)

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
    returns the number of rows changed. *)

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
(** {!run} of the statement: rows changed. A constraint violation (foreign key,
    unique, check) is a [Plugin] error like any other; only its message tells
    them apart. *)

val write_all : t -> Stmt.t list -> (unit, error) result Fut.t
(** {!write} each statement in order, stopping at the first error, which is
    returned. Not atomic: statements before the failing one stay applied. *)
