(** Development rows for the dev page [#dev/seed]: a dozen plants, tags, links
    and observations with fixed ids and timestamps. Only that page applies them
    (reachable in every build until the [#dev/*] fragments are compiled out).
    They go into the real [herbier] database: seed a throwaway install, not the
    phone that holds the collection. Every plant, tag and observation id starts
    with ["5eed"]; link ids are {!Herbier_domain.Ids.Plant_tag_id.of_key}.
    Applying {!statements} again rewrites the same rows (idempotent). The rows
    do not go through the outbox, so they are never pushed. Names and places are
    placeholders. *)

val plants : Herbier_domain.Plant.t list
val tags : Herbier_domain.Tag.t list
val plant_tags : Herbier_domain.Tag.Plant_tag.t list
val observations : Herbier_domain.Observation.t list

val statements : Stmt.t list
(** Upserts in foreign-key order: plants, tags, plant_tags, observations. *)
