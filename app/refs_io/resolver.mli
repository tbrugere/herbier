(** Resolves a shared or pasted link (architecture §7): [Link.t] plus network
    lookups → the GBIF taxon (gbif_key + partial snapshot), through {!Http.run}.
*)

val resolve : Herbier_domain.Link.t -> Herbier_refs.Resolve.outcome Fut.t
(** {!Http.run} of {!Herbier_refs.Resolve.resolve}. Never fails: a network
    problem is [Unresolved {why = Unavailable _}]. *)

val resolve_text :
  string -> (Herbier_domain.Link.t * Herbier_refs.Resolve.outcome) Fut.t
(** [Link.classify] then {!resolve}; the link is returned for display. *)
