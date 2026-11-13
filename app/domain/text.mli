(** Text rules. *)

val non_blank : string -> string option
(** [non_blank s] is [s] without its leading and trailing ASCII whitespace
    ([String.trim]: space, tab, newline, carriage return, form feed), or [None]
    when nothing is left. A non-breaking space is not whitespace here. *)
