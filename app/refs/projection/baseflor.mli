(** Life form, flowering months and habitat of a taxon, from Tela Botanica's
    Baseflor (Julve). *)

type habitat = {phrase : string option; chips : string list}

val life_form : Sources.Tela.baseflor -> string Cited.t option
(** [type_bio], trimmed; [None] when absent. *)

val months : string -> int list option
(** Baseflor's [floraison] parser, exported as [Projection.months] and
    documented there. *)

val flowering : Sources.Tela.baseflor -> int list Cited.t option
(** {!months} of [floraison]. *)

val habitat : Sources.Tela.baseflor -> habitat Cited.t option
(** [phrase] = [carac_ecolo] trimmed; [chips] = the light, soil moisture, soil
    reaction and nutrient labels in that order, each cut before its first [" ("]
    and trimmed, blank ones and duplicates dropped. [None] when both are empty.
*)
