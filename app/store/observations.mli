(** Queries on [observations]. Order of every list: [at] descending, then [id]
    descending (newest first, as in the Journal, 4c). *)

module Observation = Herbier_domain.Observation
module Observation_id = Herbier_domain.Ids.Observation_id
module Plant_id = Herbier_domain.Ids.Plant_id

val row : (Tables.Observations.t, Observation.t) Postgrest.Row.t
(** [position] is [Some {lat; lon; accuracy_m}] when [lat] and [lon] are both
    set, [None] otherwise (an [accuracy_m] without position is dropped). *)

val list : Observation.t Stmt.query
(** Every live observation. *)

val get : Observation_id.t -> Observation.t Stmt.query
(** The live observation with that id; 0 or 1 row. *)

val of_plant : Plant_id.t -> Observation.t Stmt.query
(** Live observations linked to the plant (4f, 4h), whether or not the plant
    itself is live. *)

val unidentified : Observation.t Stmt.query
(** Live observations with [plant_id] null (« À identifier »). *)

val between : from:Ptime.t -> until:Ptime.t -> Observation.t Stmt.query
(** Live observations with [from <= at < until]. For a Journal day the caller
    passes the UTC instants of local midnight. Empty when [until <= from]. *)

val to_geocode : Observation.t Stmt.query
(** Live observations with [lat] and [lon] set and [place_derived] null or blank
    after trimming ([trim(place_derived) = '']); same order as every list here
    (the newest, usually the one just recorded, first). Whether [place_label] is
    set does not matter. *)

val input : Observation.t -> (Tables.Observations.t, [`Full]) Postgrest.Input.t
(** Every column of [Tables.Observations], in its declaration order;
    [position = None] gives [lat], [lon] and [accuracy_m] null. The upsert's
    columns and the outbox payload. *)

val upsert : Observation.t -> Outbox.edit
(** Writes the whole record ({!Stmt.upsert} of {!input}); always changes the
    row, so {!Db.edit} appends one entry. Read back by [id]. Nothing is
    validated here: SQLite enforces the table's checks (lat/lon both or neither,
    ranges, accuracy ≥ 0) and foreign keys, and a record that violates them
    makes {!Db.edit} fail with a plugin error. *)

val soft_delete : Observation_id.t -> at:Ptime.t -> Outbox.edit
(** {!Stmt.soft_delete}; read back by [id] whatever [deleted_at]. Appends an
    entry (payload with [deleted_at = at]) when the observation was live,
    nothing when it is absent or already deleted. Its photos are untouched. *)

val set_place_derived :
  Observation_id.t ->
  lat:float ->
  lon:float ->
  string ->
  at:Ptime.t ->
  Outbox.edit
(** [update observations set place_derived = ?, updated_at = ? where id = ? and
     deleted_at is null and lat = ? and lon = ? and (place_derived is null or
     trim(place_derived) = '')], read back by [id]. One change (and one outbox
    entry carrying the whole row, [place_derived] and [updated_at = at] set)
    when the observation is live, still at [lat]/[lon] (the position the name
    was computed for) and still without a derived name; no change and no entry
    when it was deleted, moved or got a name meanwhile. No other column is
    touched. *)
