(** The envelope of the versioned JSON documents sync reads (the stored session,
    the keep-alive job's answers): an object with ["v"]. Pure (test/sync copies
    it). *)

val object_of_string : string -> ((string * Yojson.Safe.t) list, string) result
(** The fields of a JSON object. [Error "not JSON"] (Yojson's message is
    dropped: it quotes the input, which may be a token),
    [Error "not an object"]. *)

val version : int -> (string * Yojson.Safe.t) list -> (unit, string) result
(** [Ok ()] when ["v"] is that integer; [Error "unknown version"] when it is
    something else, [Error "no version"] when it is absent. *)

val versioned : int -> string -> ((string * Yojson.Safe.t) list, string) result
(** {!object_of_string}, then {!version}. *)
