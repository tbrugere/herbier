(** A plant row's identity and version, for the list diffs and the change tests
    of the screens. *)

val same : Herbier_domain.Plant.t -> Herbier_domain.Plant.t -> bool
(** The same plant: equal ids. *)

val equal : Herbier_domain.Plant.t -> Herbier_domain.Plant.t -> bool
(** The same plant at the same version: equal ids and [updated_at]. *)
