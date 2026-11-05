(** Plumbing shared by the [Cap_*] bindings: plugin lookup on
    [globalThis.herbier] and promise → [Fut] conversion with errors mapped to
    {!Cap_error.t}. Used only inside [app/bindings/]. *)

val plugin : string -> (Jv.t, Cap_error.t) result
(** [plugin name] is [globalThis.herbier.<name>]; [Error (Unavailable name)]
    when [globalThis.herbier] or that key is undefined or null. *)

val call :
  string ->
  string ->
  Jv.t array ->
  ok:(Jv.t -> ('a, Cap_error.t) result) ->
  ('a, Cap_error.t) result Fut.t
(** [call name meth args ~ok] looks up [plugin name], calls its method [meth]
    with [args], and maps the promise it returns: resolved [v] → [ok v];
    rejected [e] → [Error (rejected e)]. A synchronous throw by the call (method
    missing, plugin throwing an Error, a string or another printable value
    before returning a promise) is [Error (Rejected _)] too. [ok] must not raise
    (an exception inside a promise callback would leave the future
    undetermined); it reads fields with {!field} and friends. *)

val on :
  Jv.t ->
  string ->
  Jv.t array ->
  ok:(Jv.t -> ('a, Cap_error.t) result) ->
  ('a, Cap_error.t) result Fut.t
(** Same as {!call} on an object already in hand (an [SQLiteDBConnection], a
    listener handle) instead of a [globalThis.herbier] key. *)

val rejected : Jv.t -> Cap_error.t
(** The [Rejected] mapping described in {!Cap_error.t}. *)

val unit_ok : Jv.t -> (unit, Cap_error.t) result
(** An [ok] for methods whose resolved value carries nothing: always [Ok ()]. *)

val field : Jv.t -> string -> (Jv.t, Cap_error.t) result
(** [field v path] follows a dot-separated [path] (["changes.changes"]);
    [Error (Unexpected path)] when any step is undefined or null. *)

(** {1 Typed fields}

    {!field} plus a [typeof] check (["string"], ["number"], ["boolean"]);
    [Error (Unexpected path)] on a type mismatch. [int_field] also requires an
    integer within OCaml's [int] range (32 bits under jsoo), else
    [Error (Unexpected path)]; it never truncates. *)

val string_field : Jv.t -> string -> (string, Cap_error.t) result
val int_field : Jv.t -> string -> (int, Cap_error.t) result
val bool_field : Jv.t -> string -> (bool, Cap_error.t) result
