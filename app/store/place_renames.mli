(** The device-only [place_renames] table (schema migration 7): the observations
    named before the commune-first rule, which the geocoding pass renames once
    and then forgets. Not synced: written with {!Herbier_store_io.Db.write},
    never through {!Herbier_store_io.Db.edit}, no outbox entry. The observations
    to rename are read with {!Observations.to_rename}. *)

val forget : Herbier_domain.Ids.Observation_id.t -> Stmt.t
(** [delete from place_renames where observation_id = ?] (a hard delete: the
    table is not synced): 1 change, or 0 when absent. *)

val count : int Stmt.query
(** The number of rows ([select count(…) as n]): one row, for the dev page. *)
