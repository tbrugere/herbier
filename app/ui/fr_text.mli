(** Counted French text. Pure. *)

val plural : int -> string -> string -> string
(** [plural n one many] is ["n one"] for [n <= 1] (French: 0 and 1 take the
    singular), ["n many"] otherwise: [plural 2 "plante" "plantes"] is
    ["2 plantes"]. *)
