(** The photos on their way to an observation (M8.88): captures 4d's Enregistrer
    handed over while still pending, counted per observation so that 4h shows a
    loading tile for each until it is written (or failed), and knows whether one
    was written before its own reload shows it. Pure; shared through {!State}.
*)

module Observation_id := Herbier_domain.Ids.Observation_id

type t

val empty : t
val equal : t -> t -> bool

val add : Observation_id.t -> t -> t
(** One more photo on its way to the observation. *)

val settle : written:bool -> Observation_id.t -> t -> t
(** One of them landed ([written]) or failed: one fewer on its way. None on its
    way → unchanged. Never raises. *)

val on_way : Observation_id.t -> t -> int
(** How many are still on their way; [0] for an unknown observation. *)

val written : Observation_id.t -> t -> int
(** How many of them landed so far. *)
