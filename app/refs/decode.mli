(** Errors and helpers shared by the source decoders ([Sources.*]).

    Field rules: a {e required} field missing or of the wrong JSON type is an
    [Error (Unexpected _)]; an {e optional} field missing, [null], of the wrong
    type, or a string blank after trimming is [None] (style §8.4). Strings are
    returned as given, not trimmed. Integers accept [`Int] only. Nothing here
    raises. *)

type error =
  | Not_json of string  (** The body is not JSON; the parser's message. *)
  | Unexpected of {path : string; expected : string}
      (** A required field is missing or has the wrong type. [path] is a JSON
          pointer from the payload root (["/usageKey"], ["/query/search"], [""]
          for the root itself); [expected] names the JSON type or values wanted
          (["int"], ["array"], ["EXACT|FUZZY|HIGHERRANK|NONE"]). *)
  | Api_error of {code : string; info : string}
      (** The API answered 200 with an error object (Wikidata's
          [{"error":{"code","info"}}]). *)

val error_to_string : error -> string
val equal_error : error -> error -> bool

val json_of_string : string -> (Yojson.Safe.t, error) result
(** [Yojson.Safe.from_string], with any exception turned into [Not_json]. Never
    raises. *)

(** {1 Field helpers}

    [at] is the JSON pointer of the object the field is read from ([""] for the
    root, the default); errors report [at ^ "/" ^ name]. *)

val member : string -> Yojson.Safe.t -> Yojson.Safe.t option
(** The field of an object; [None] when absent, [null], or when the value is not
    an object. *)

val string : string -> Yojson.Safe.t -> string option
(** An optional non-blank string field. *)

val int : string -> Yojson.Safe.t -> int option
(** An optional [`Int] field. *)

val bool : string -> Yojson.Safe.t -> bool option
(** An optional boolean field. *)

val list : string -> Yojson.Safe.t -> Yojson.Safe.t list
(** An optional array field; [[]] when absent or not an array. *)

val non_blank : string -> string option
(** [Some s] when [s] is not blank after trimming. *)

val is_digits : string -> bool
(** [s] is not empty and only ASCII digits. *)

val required_string :
  ?at:string -> string -> Yojson.Safe.t -> (string, error) result
(** A required non-blank string field (a blank one is [Unexpected]). *)

val required_int : ?at:string -> string -> Yojson.Safe.t -> (int, error) result

val required_list :
  ?at:string -> string -> Yojson.Safe.t -> (Yojson.Safe.t list, error) result

val unexpected : string -> string -> ('a, error) result
(** [unexpected path expected] is [Error (Unexpected {path; expected})]. *)

module Syntax : sig
  val ( let* ) :
    ('a, error) result -> ('a -> ('b, error) result) -> ('b, error) result

  val ( let+ ) : ('a, error) result -> ('a -> 'b) -> ('b, error) result
end
