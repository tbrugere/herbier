(** Place names (architecture §8): the background geocoding of new observations
    and the 4m source switches. Documented in {!App}. *)

val geocode_pending : Core.t -> unit

val settings_key :
  Herbier_geo.Place_name.source -> bool Herbier_store.Settings.key

val set_place_source : Core.t -> Herbier_geo.Place_name.source -> bool -> unit
val place_error : Core.t -> string option React.signal

val save :
  Core.t ->
  Herbier_store.Outbox.edit list ->
  (int, Herbier_store_io.Db.error) result Fut.t
(** {!Core.commit}, then {!geocode_pending} after a commit that changed rows. *)
