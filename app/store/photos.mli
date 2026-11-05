(** Queries on [photos] rows. *)

module Photo = Herbier_domain.Photo
module Photo_id = Herbier_domain.Ids.Photo_id
module Observation_id = Herbier_domain.Ids.Observation_id
module Plant_id = Herbier_domain.Ids.Plant_id

val row : (Tables.Photos.t, Photo.t) Postgrest.Row.t

val get : Photo_id.t -> Photo.t Stmt.query
(** The live photo with that id; 0 or 1 row. *)

val of_observation : Observation_id.t -> Photo.t Stmt.query
(** Live photos of the observation, ordered by [taken_at] ascending then [id]
    (the 4d/4h strip). *)

val of_plant : Plant_id.t -> Photo.t Stmt.query
(** Live photos of the plant's live observations, ordered by [taken_at]
    descending then [id] descending (the 4f hero picks the cover, else the
    first). *)

val upsert : Photo.t -> Stmt.t
(** Writes the whole record (see {!Stmt.upsert}). *)

val soft_delete : Photo_id.t -> at:Ptime.t -> Stmt.t
(** See {!Stmt.soft_delete}. *)
