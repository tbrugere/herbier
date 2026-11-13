(** 4m's card under « File d'envoi », only when there is something to show: «
    Réception bloquée » with the stop when the engine's last pull stopped on a
    {!Herbier_sync.Cycle.Outcome.persistent} outcome, then, when outbox entries
    are parked, « Non synchronisé · <n> » and one row per entry
    ({!Parked_entry.describe}). Read at mount and again on {!App.synced} (only a
    cycle parks an entry or stops a pull); a first read that fails shows « File
    d'envoi illisible ». *)

val v : App.t -> Brr.El.t * Rb.binding list
(** The host element (display: contents, so an empty card leaves no gap) and its
    bindings. *)
