(** [Element.setPointerCapture], missing from Brr 0.0.9: after it, the element
    receives every event of that pointer until it is released, even when the
    finger leaves it (a drag). *)

val set : Brr.El.t -> int -> unit
(** [set el pointer_id], best effort: any exception the browser throws (a
    pointer no longer active, an element not in the document) is swallowed and
    the pointer is simply not captured. *)
