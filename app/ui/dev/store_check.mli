(** Dev-only page: runs {!Herbier_store.Db} against the real plugin and lists
    one line per check, "ok" or the error. Reached with the URL fragment
    [#dev/store]. *)

val el : unit -> Brr.El.t
(** A fresh element that starts the checks when created. Uses three new
    databases per run, [herbier_dev_store_<ms>_fresh],
    [herbier_dev_store_<ms>_empty] and [herbier_dev_store_<ms>_newer] ([<ms>] =
    epoch milliseconds when the run starts), never [herbier]; their files
    remain. *)
