(** A new observation's GPS fix as 4d and 4j wait for it. Pure; the fix itself
    is taken by {!Gps_fix}. *)

type t =
  | Searching
  | Fix of Herbier_domain.Observation.position
  | No_fix  (** The fix failed or timed out: the observation has none. *)

val position : t -> Herbier_domain.Observation.position option
(** [Fix p] → [Some p]; [Searching], [No_fix] → [None]. *)
