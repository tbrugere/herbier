(** The « IGN hors-ligne » packs (architecture §8): download and delete, one
    département or « Toute la France ». Documented in {!App}. *)

val packs : Core.t -> Core.pack list React.signal

type pack_error = Core.pack_error =
  | Busy
  | Offline
  | Pack of Herbier_geo_io.Commune_packs.error

val pack_error_to_string : pack_error -> string

val departements :
  Core.t -> (Herbier_geo.Communes.departement list, pack_error) result Fut.t

val downloading : Core.t -> Herbier_geo.Communes.departement option React.signal

val download_pack :
  Core.t -> Herbier_geo.Communes.departement -> (unit, pack_error) result Fut.t

val delete_pack :
  Core.t -> Herbier_geo.Communes.Code.t -> (unit, pack_error) result Fut.t

type france = Core.france =
  | France_idle
  | France_starting
  | France_running of {
      step : pack_error Herbier_geo.France_packs.step;
      cancelling : bool;
    }
  | France_finished of pack_error Herbier_geo.France_packs.outcome
  | France_deleting

val is_running : france -> bool
val is_busy : france -> bool
val france : Core.t -> france React.signal

val france_plan :
  ?only:Herbier_geo.Communes.Code.t list ->
  Core.t ->
  (Herbier_geo.France_packs.plan, pack_error) result Fut.t

val connection : Core.t -> Herbier_bindings.Cap_network.connection Fut.t

val download_france :
  Core.t ->
  Herbier_geo.France_packs.plan ->
  (pack_error Herbier_geo.France_packs.outcome, pack_error) result Fut.t

val france_cause : pack_error -> Herbier_geo.France_packs.cause
val france_failure : pack_error -> Herbier_geo.France_packs.failure
val cancel_france : Core.t -> unit
val delete_all_packs : Core.t -> (unit, pack_error) result Fut.t
