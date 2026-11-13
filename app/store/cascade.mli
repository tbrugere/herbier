(** Soft deletes that take a record's dependents with it, all at one instant
    (handoff 5a). Pure: the edits for one {!Herbier_store_io.Db.edit}, each soft
    delete appending its own outbox entry. The ids are the live dependents as
    the caller read them; a dependent already deleted appends nothing. *)

module Ids := Herbier_domain.Ids

val plant :
  at:Ptime.t ->
  photos:Ids.Photo_id.t list ->
  observations:Ids.Observation_id.t list ->
  tags:Ids.Tag_id.t list ->
  Ids.Plant_id.t ->
  Outbox.edit list
(** The plant, its observations, their photos and its tag links; the tags
    themselves stay. [photos] are those of {!Photos.of_plant}, [observations] of
    {!Observations.of_plant}, [tags] of {!Tags.of_plant}. *)

val observation :
  at:Ptime.t ->
  photos:Ids.Photo_id.t list ->
  Ids.Observation_id.t ->
  Outbox.edit list
(** The observation and its photos ({!Photos.of_observation}). *)
