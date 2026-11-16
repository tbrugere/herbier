(** 4m's card under « File d'envoi », only when there is something to show: «
    Serveur en pause » when the engine's last cycle stopped on a paused project
    ({!Herbier_ui_model.Server_text.paused}), with a link to the hosted
    project's dashboard when {!Herbier_sync.Backend.supabase_url} is one; then «
    Réception bloquée » with the stop when the engine's last pull stopped on a
    {!Herbier_sync_core.Cycle.Outcome.persistent} outcome, then, when outbox
    entries are parked, « Non synchronisé · <n> » and one row per entry
    ({!Herbier_ui_model.Parked_entry.describe}). Read at mount and again on
    {!App.synced} (only a cycle parks an entry or stops a pull); a first read
    that fails shows « File d'envoi illisible ». *)

val v : App.t -> Brr.El.t * Rb.binding list
(** The host element (display: contents, so an empty card leaves no gap) and its
    bindings. *)
