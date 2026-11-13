(** 4j's state machine: resolution, offline, fallback to 4i. Documented as
    [Intercept]'s values of the same names. *)

module Link := Herbier_domain.Link
module Plant := Herbier_domain.Plant
module Candidate := Herbier_refs.Resolve.Candidate
module Taxon := Herbier_refs.Sources.Gbif.Taxon

type status =
  | Offline
  | Resolving
  | Failed of string
  | Found of {candidate : Candidate.t; existing : Plant.t option}
  | Search of string

val equal_status : status -> status -> bool

type t

val link : t -> Link.t
val status : t -> status
val seq : t -> int

type effect_ =
  | No_effect
  | Resolve of {seq : int}
  | Name of {seq : int; taxon : Taxon.t}

val init : online:bool -> plants:Plant.t list -> string -> t * effect_
val resolved : seq:int -> Herbier_refs.Resolve.outcome -> t -> t * effect_
val named : seq:int -> Candidate.t -> t -> t
val network : online:bool -> t -> t * effect_
val retry : online:bool -> t -> t * effect_
val search_query : t -> string
