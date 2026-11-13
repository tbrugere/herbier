(** A département code, checked once: the only kind of value that reaches the
    CQL filter and a pack's file name. *)

type t

val of_string : string -> t option
(** [Some] for two digits (["01"]…["95"]), ["2A"], ["2B"], three digits starting
    with ["97"] (["971"]…["976"]); [None] otherwise ([""], ["2a"], ["1"],
    ["20"], ["9a"], ["'"], ["68' or 1=1"]). No quote can get through. *)

val to_string : t -> string
val equal : t -> t -> bool

val compare : t -> t -> int
(** String order. *)
