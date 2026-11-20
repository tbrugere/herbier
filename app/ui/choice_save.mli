(** The store writes that put an « À identifier » observation on a plant: a
    proposal chosen in the identification layer (4k's 6j, 4h) and 4k's own
    picks. *)

val save :
  App.t ->
  at:Ptime.t ->
  Herbier_domain.Observation.t ->
  Herbier_ui_model.Observation_plan.write ->
  (unit, Herbier_store_io.Db.error) result Fut.t
(** Moves the observation onto the write's plant, dated [at]: [Attach] onto an
    existing plant; [Create_free] stores the new plant first (the observation
    references it); [Create_linked] goes through {!App.create_linked}, the
    observation's move as its [extra]. One save each, so a failure writes
    nothing. [Error e] is the caller's to log and show; never raises. *)
