(** References (architecture §6): a plant's fetch, its organ thumbnails and its
    GBIF link. Documented in {!App}. *)

type link_error = Plant_gone | Store of Herbier_store_io.Db.error

val fetching : Core.t -> Herbier_domain.Ids.Plant_id.t list React.signal
val refresh : Core.t -> Herbier_domain.Ids.Plant_id.t -> unit
val refresh_if_due : Core.t -> Herbier_domain.Ids.Plant_id.t -> unit

val link :
  Core.t ->
  ?name:string ->
  Herbier_domain.Ids.Plant_id.t ->
  Herbier_refs.Sources.Gbif.Taxon.t ->
  (unit, link_error) result Fut.t

val create_linked :
  Core.t ->
  ?extra:Herbier_store.Outbox.edit list ->
  Herbier_domain.Plant.t ->
  Herbier_refs.Sources.Gbif.Taxon.t ->
  (unit, Herbier_store_io.Db.error) result Fut.t

type free_error =
  | Busy
  | Store of Herbier_store_io.Db.error
  | Files of Herbier_bindings.Cap_error.t

val offline_usage :
  unit ->
  (Herbier_ui_model.Offline_data.usage, Herbier_bindings.Cap_error.t) result
  Fut.t

val free_reference_photos : Core.t -> (unit, free_error) result Fut.t
