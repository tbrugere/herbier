(** SQLite values for the local store, as pure functions: {!Postgrest.Col}
    values to bound parameters, and the plugin's JSON row text to
    {!Postgrest.Row} values. *)

(** A bound parameter; {!Db} maps it one to one onto [Cap_sqlite.value]. *)
type param = Null | Int of int | Float of float | Text of string

val param : ('table, 'a, 'optional) Postgrest.Col.t -> 'a -> param
(** [param col v] is how the store writes [v] into [col]'s SQLite column:
    - [Nullable _], [None] → [Null]; [Nullable b], [Some v] → as [Not_Null b]
      [v];
    - [Integer] → [Int]; [Numeric] → [Float]; [Bool] → [Int 1] / [Int 0];
    - [Str] → [Text]; [Custom c] → [Text] of [c.to_json v]: the bare string when
      it is a JSON string (ids, lookup values), else its JSON text;
    - [TimestampTz] → [Text (timestamp v)];
    - [JSON] → [Text (Yojson.Safe.to_string v)].

    Never raises. Only a [Custom] codec whose [to_json] gives a JSON string
    round-trips locally. Four values do not read back as written, so writers
    must not produce them: a [Custom] value whose [to_json] is not a JSON string
    (its text reads back as a JSON string, and {!json} takes only [JSON]
    columns), a [Bool] (Row wants a JSON bool; no table has one), a JSON [`Null]
    (Row reads it as a SQL null, as with PostgREST), and a non-finite float (the
    plugin bridge turns NaN and infinities into SQL null). *)

val timestamp : Ptime.t -> string
(** Fixed-width RFC 3339 in UTC with microseconds,
    ["YYYY-MM-DDTHH:MM:SS.ffffffZ"] (27 characters), so that text order is time
    order in SQL ([ORDER BY updated_at], [updated_at > ?]). Sub-microsecond
    digits are truncated (Postgres rounds them; the app's clocks carry none). *)

val text :
  name:string ->
  to_string:('a -> string) ->
  of_string:(string -> 'a option) ->
  'a Postgrest.Col.custom
(** A [Custom] codec exchanging [to_string v] as a JSON string, the shape that
    round-trips locally (see {!param}); its [of_json] is [of_string] of a JSON
    string and [None] for any other JSON value. For the local-only columns; the
    synced columns' codecs come with {!Tables}. *)

type 'table json_column
(** A result column holding JSON text, of the table ['table]. *)

val json :
  ('table, Yojson.Safe.t, 'optional) Postgrest.Col.t -> 'table json_column
(** [json col] names [col] (a [Not_Null JSON] column) for [~json]. *)

type error =
  | Invalid_row of string
      (** The row text is not a JSON object; carries the parser's message or
          ["not an object"]. *)
  | Invalid_json_column of string
      (** A column listed in [~json] holds a string that is not JSON text;
          carries the column name. *)
  | Row of Postgrest.Row.error  (** {!Postgrest.Row.decode} failed. *)

val decode :
  json:'table json_column list ->
  ('table, 'a) Postgrest.Row.t ->
  string ->
  ('a, error) result
(** [decode ~json spec text] parses one row as returned by [Cap_sqlite.query] (a
    JSON object [{"column": value, …}]), replaces the value of each column in
    [json] that is a JSON string by the JSON it contains (SQLite keeps JSON
    columns as TEXT), then decodes the object with [spec]. [json] is required so
    that every caller states its JSON columns ([~json:[]] when none): a JSON
    column left out would decode as a JSON string and be written back
    double-encoded. Columns of [json] absent from the row, or whose value is not
    a string ([null], an already-parsed array), are left alone (the spec then
    reports [`Missing] / [`UnexpectedNull] as usual). Never raises: a [Failure]
    escaping [Postgrest.Row.decode] is [Error (Row `WrongType)]; this covers an
    integer literal out of range and also a [Failure] raised by a mapper of
    [spec], so mappers must be total. *)

val decode_value :
  ('table, 'a) Postgrest.Row.t ->
  Yojson.Safe.t ->
  ('a, Postgrest.Row.error) result
(** [Postgrest.Row.decode] that never raises: a [Failure] escaping it (an
    integer literal out of range, a mapper of the spec) is [`WrongType]. The
    last step of {!decode}. *)

val row_error_to_string : Postgrest.Row.error -> string
(** ["missing column"], ["not an object"], ["wrong type"], ["unexpected null"],
    ["dummy row spec"]. *)

val error_to_string : error -> string
(** One line for logs and the dev page. *)
