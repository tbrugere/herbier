(** The store edits of a {!Herbier_ui_model.Plant_form.change}: 5a's «
    Enregistrer » and the fiche's « + tag » both save through here. *)

val of_change :
  at:Ptime.t ->
  plant:Herbier_domain.Ids.Plant_id.t ->
  Herbier_ui_model.Plant_form.change ->
  Herbier_domain.Tag.t list * Herbier_store.Outbox.edit list
(** The tags created (fresh ids, [created_at = updated_at = at]) and the edits,
    in this order: the plant upserted with [updated_at = at] when it changed,
    the new tags, the links to the existing and new tags, the unlinks. *)
