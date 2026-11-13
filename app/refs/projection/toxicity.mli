(** The toxicity sentence of a taxon, from its Wikipedia summary. *)

val toxicity : Sources.Wikipedia.t -> string Cited.t option
(** The first sentence of the extract that speaks of toxicity ([toxique],
    [toxic], [vénéneu], [poison], case-folded), else the description when it
    does; for a standard page only. *)
