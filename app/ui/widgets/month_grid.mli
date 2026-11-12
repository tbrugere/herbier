(** « Floraison » (4f): twelve month cells, the given months highlighted. *)

val v : int list -> Brr.El.t
(** A [div.month-grid] with [aria-hidden="true"] (decorative: the caller shows
    [Ref_text.months_text] beside it); twelve [span.month-grid__cell] with
    [Ref_text.month_letter], the months in the list (1..12) carrying
    [is-active]. Not interactive. *)
