(** Dev-only page: runs {!Herbier_store_io.Db} against the real plugin and lists
    one line per check, "ok" or the error. Reached with the URL fragment
    [#dev/store]. Besides opening, migrating and round-tripping a plants row, it
    checks on the fresh database that {!Herbier_store.Search} finds "Digitale
    pourpre" and "Digitalis" for ["digitale"] (FTS5 and the migration 2 triggers
    work through the plugin), that a setting reads back, and the outbox group:
    {!Herbier_store_io.Db.edit} appends one entry per changed row, rolls back
    the rows and entries of a failing edit (no transaction left open
    afterwards), stays atomic when a plain write is started before it settles,
    and {!Herbier_store.Outbox.park} / {!Herbier_store.Outbox.delete} take an
    entry out of {!Herbier_store.Outbox.next}; and the group « transaction sans
    entrée »: {!Herbier_store_io.Db.bare_transaction} commits an observation
    written before its plant (foreign keys deferred, [defer_foreign_keys] 1
    inside and 0 after the commit) and appends no entry, while an observation
    whose plant is never written fails with [Foreign_key] before the commit,
    rolled back, and a later write still works. *)

val el : unit -> Brr.El.t
(** A fresh element that starts the checks when created. Uses three new
    databases per run, [herbier_dev_store_<ms>_fresh],
    [herbier_dev_store_<ms>_empty] and [herbier_dev_store_<ms>_newer] ([<ms>] =
    epoch milliseconds when the run starts), never [herbier]; their files
    remain. *)
