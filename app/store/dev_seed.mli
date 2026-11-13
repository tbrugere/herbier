(** Development rows for the dev page [#dev/seed]: a dozen plants, tags, links
    and observations with fixed ids and timestamps. Only that page applies them
    (dev builds only: release builds link no [#dev/*] page). They go into the
    real [herbier] database: seed a throwaway install, not the phone that holds
    the collection. Every plant, tag and observation id starts with ["5eed"];
    link ids are {!Herbier_domain.Ids.Plant_tag_id.of_key}. Applying
    {!statements} again rewrites the same rows (idempotent). The rows do not go
    through the outbox, so they are never pushed. Names and places are
    placeholders. *)

val plants : Herbier_domain.Plant.t list
val tags : Herbier_domain.Tag.t list
val plant_tags : Herbier_domain.Tag.Plant_tag.t list
val observations : Herbier_domain.Observation.t list

val statements : Outbox.bare list
(** Upserts in foreign-key order: plants, tags, plant_tags, observations. The
    bare statements of the per-table edits ({!Outbox.without_entry}) and
    {!Tags.upsert_plant_tag}, applied in one [Db.bare_transaction] (atomic):
    they append no outbox entry. *)
