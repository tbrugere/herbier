(** String checks the tests share. *)

val contains : sub:string -> string -> bool
(** [contains ~sub s] is true when [sub] occurs in [s]; the empty [sub] occurs
    in every string. *)
