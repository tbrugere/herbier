(** Dev-only page for 4a: shows the Collection screen over the app's [herbier]
    database, or why there is none. Seed it first with [#dev/seed]. Reached with
    the URL fragment [#dev/collection]. *)

val el : (Herbier_store.Db.t, string) result -> Brr.El.t
