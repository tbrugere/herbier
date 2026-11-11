(** A Wikidata item id. *)

type t

val of_string : string -> t option
(** ["Q"] then 1 to 12 ASCII digits, the first not ['0'] (["Q157555"]); [None]
    otherwise (["q1"], ["Q0"], ["Q01"], ["P846"], [" Q1"]). *)

val to_string : t -> string
val equal : t -> t -> bool
