(** Dev-only page for spike 3 (architecture §10): the positron map over the
    app's [herbier] database. Seed it with [#dev/seed] first. Reached with
    [#dev/map].

    A status line
    [observations: <total> · placées: <placeable> · rendues: <rendered>],
    refreshed after every camera move and whenever the map settles; the map,
    framed on the placeable observations; a log of clicks
    ([clic <lat>,<lon> → <ids>], the first one's accuracy circle shown and the
    map flown to it), camera reads and MapLibre errors ([erreur: …]).
    [herbierDev.mapRendered()] is the number of observation points rendered (0
    before the map exists). *)

val el : (Herbier_store_io.Db.t, string) result -> Brr.El.t
