(** Dev-only page [#dev/sync]: the sync engine on the device. Shows the account
    status, the outbox (count and parked entries), the pull cursors
    ({!Herbier_store.Sync_state.all}), the engine's
    {!Herbier_sync.Cycle.Schedule} state and its last cycle (push counts,
    per-table pull report, stop), redrawn after every cycle ({!App.synced}) and
    on « Actualiser ». Buttons: « Importer la session »
    ({!Herbier_sync.Auth.debug_import} of the pasted output of
    scripts/local-session.sh, since an emulator has no Google account), «
    Synchroniser » ({!Herbier_sync.Engine.sync_now}), « Curseurs à zéro » (the
    cursors reset: the next pull reads every table from the start), « Entrée
    refusée » (an outbox entry for an observation with a full position and a
    negative [accuracy_m], which survives push's decode and re-encode and which
    the server's [observations_accuracy_nonnegative] check rejects with a 400)
    and « Entrée illisible » (an entry for the table ["nope"]); both raw entries
    are inserted without their row and send the engine a local write. Prints
    [done] once first drawn. Never prints a token. *)

val el : (App.t, string) result -> Brr.El.t
