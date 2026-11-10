(** Keeping OCaml values alive from the DOM. js_of_ocaml removes code whose
    result is unused, [ignore (Sys.opaque_identity v)] included, so a closure
    cannot be relied on to keep [v] reachable; a property of a DOM node can. *)

val on : Brr.El.t -> 'a -> unit
(** [on el v] makes [v] reachable for as long as [el] is: it is appended to an
    array stored in a property of [el]. *)
