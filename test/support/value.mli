(** Literal values the suites build their rows from. *)

val time : string -> Ptime.t
(** An RFC 3339 literal; [Invalid_argument "fixture time <s>"] when it is not
    one. *)

val uuid4 : int -> string
(** ["00000000-0000-4000-8000-<n>"], [n] as 12 hex digits: a version 4 shape. *)

val uuid7 : int -> string
(** ["01965d4e-0000-7000-8000-<n>"], [n] as 12 hex digits: a version 7 shape,
    the ids scripts/record-sync-fixtures.sh writes. *)

val id : string -> (string -> 'a option) -> string -> 'a
(** [id what of_string s]: [of_string s]; [Invalid_argument "fixture <what>"]
    when it gives [None]. *)
