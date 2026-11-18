(** The Identifier glyph (handoff « Bouton Identifier · glyphe », variant A): a
    viewfinder frame around a leaf, as inline SVG in [currentColor]; the vein is
    cut out, so the background shows through. Material Symbols has no such
    glyph. *)

val el : ?size:int -> unit -> Brr.El.t
(** An [<svg class="identify-glyph" aria-hidden="true">] of [size] px; [size]
    default 24. *)
