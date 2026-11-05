(** Debug page [#dev/seed], shipped in every build until the router compiles the
    [#dev/*] fragments out. It opens the app's database ([herbier]) and applies
    {!Herbier_store.Dev_seed.statements}. It then lists the counts of live
    plants, tags and observations, and the display names
    {!Herbier_store.Search.plants} returns for ["digitale"]. Each step prints
    one line, "ok" or the error. Finally it closes the database (also after a
    failed step). *)

val el : unit -> Brr.El.t
(** A fresh element that starts the steps when created. Writes the seed's rows
    into [herbier] and nothing else; they stay. *)
