(** A value and the sources it came from, in [Reference.Source.all] order,
    without duplicates ("Toute donnée cite sa source"). *)

type 'a t = {value : 'a; sources : Herbier_domain.Reference.Source.t list}

val v : Herbier_domain.Reference.Source.t list -> 'a -> 'a t
(** [v sources value]. *)
