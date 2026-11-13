(** Resolves a shared or pasted link (architecture §7): [Link.t] plus network
    lookups → the GBIF taxon (gbif_key + partial snapshot), through {!Http.run}.
*)

val resolve : Herbier_domain.Link.t -> Herbier_refs.Resolve.outcome Fut.t
(** {!Http.run} of {!Herbier_refs.Resolve.resolve}. Never fails: a network
    problem is [Unresolved {why = Unavailable _}]. *)

val resolve_text :
  string -> (Herbier_domain.Link.t * Herbier_refs.Resolve.outcome) Fut.t
(** [Link.classify] then {!resolve}; the link is returned for display. *)

val search :
  q:string ->
  ( Herbier_refs.Resolve.Candidate.t list,
    Herbier_refs.Resolve.unresolved )
  result
  Fut.t
(** {!Http.run} of {!Herbier_refs.Resolve.search}. Never fails: a network
    problem is [Error (Unavailable _)]. *)

val chosen :
  Herbier_refs.Sources.Gbif.Taxon.t ->
  (Herbier_refs.Sources.Gbif.Taxon.t, Herbier_refs.Resolve.unresolved) result
  Fut.t
(** {!Http.run} of {!Herbier_refs.Resolve.chosen}; determined without network
    for a non-synonym. *)

val named :
  Herbier_refs.Sources.Gbif.Taxon.t ->
  (Herbier_refs.Resolve.Candidate.t * string option) Fut.t
(** {!Http.run} of {!Herbier_refs.Resolve.named}; never fails (offline:
    [french = []] and the failure). *)
