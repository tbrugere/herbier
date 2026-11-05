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

val upsert : Observation.t -> Stmt.t
(** Writes the whole record (see {!Stmt.upsert}). [position = None] writes
    [lat], [lon] and [accuracy_m] as null. Nothing is validated here: SQLite
    enforces the table's checks (lat/lon both or neither, ranges, accuracy ≥ 0),
    and a record that violates them makes [Db.write] fail with a plugin error.
*)

val soft_delete : Observation_id.t -> at:Ptime.t -> Stmt.t
(** See {!Stmt.soft_delete}. Its photos are untouched. *)
