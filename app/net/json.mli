(** Reading a JSON payload. *)

val parse : string -> (Yojson.Safe.t, string) result
(** [Yojson.Safe.from_string]. Malformed text raises [Json_error], whose message
    is the [Error]; under js_of_ocaml a deeply nested text raises [Failure] (a
    JS stack overflow) instead, and any other exception is an [Error] of
    [Printexc.to_string]. Never raises. *)

val member : string -> Yojson.Safe.t -> Yojson.Safe.t option
(** The field of an object; a missing field, [null] or a non-object → [None]. *)

val number : Yojson.Safe.t -> float option
(** An [`Int], or a finite [`Float]; anything else → [None]. *)

val is_digits : string -> bool
(** Non-empty and only ASCII digits. *)
