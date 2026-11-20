(** Who opened the identification layer, and what a proposal's button does there
    (architecture §12). Pure. *)

type place = {index : int; total : int}
(** A 1-based [index] of [total] in 4k's « À identifier » queue. *)

val equal_place : place -> place -> bool

type t =
  | Observation  (** 4h and #dev/identify's default caller *)
  | Queue of place option
      (** 4k's « À identifier » queue (6j); [None]: the observation is no longer
          in it *)
  | Free_name of Herbier_domain.Ids.Plant_id.t
      (** 4g: the free-name plant (6k) *)

val equal : t -> t -> bool

type action = Link  (** « Lier » *) | Create  (** « + Créer » *)

val equal_action : action -> action -> bool
val pp_action : Format.formatter -> action -> unit
val show_action : action -> string

val action : t -> owned:bool -> action
(** [Observation], [Queue _] → [Link] when [owned], else [Create]; [Free_name _]
    → [Link]. *)

val current : t -> Herbier_domain.Ids.Plant_id.t option
(** [Free_name id] → [Some id] (excluded from {!Owned.find}); else [None]. *)
