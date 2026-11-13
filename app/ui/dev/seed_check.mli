(** Dev-only page [#dev/seed]. Over the app's database ([herbier]) it applies
    {!Herbier_store.Dev_seed.statements}, then lists the counts of live plants,
    tags and observations, and the display names {!Herbier_store.Search.plants}
    returns for ["digitale"]. Each step prints one line, "ok" or the error. *)

val el : (Herbier_store_io.Db.t, string) result -> Brr.El.t
(** A fresh element that starts the steps when created, or says why there is no
    database. Writes the seed's rows into [herbier] and nothing else; they stay.
*)
