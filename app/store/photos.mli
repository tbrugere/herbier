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

val live : Photo.t Stmt.query
(** Every live photo of a live observation, ordered as {!of_plant}: the 4a
    covers, grouped by the caller through the observations' plants. *)

val input : Photo.t -> (Tables.Photos.t, [`Full]) Postgrest.Input.t
(** Every column of [Tables.Photos], in its declaration order. The upsert's
    columns and the outbox payload. *)

val upsert : Photo.t -> Outbox.edit
(** Writes the whole record ({!Stmt.upsert} of {!input}); always changes the
    row, so {!Herbier_store_io.Db.edit} appends one entry. Read back by [id]. *)

val soft_delete : Photo_id.t -> at:Ptime.t -> Outbox.edit
(** {!Stmt.soft_delete}; read back by [id] whatever [deleted_at]. Appends an
    entry (payload with [deleted_at = at]) when the photo was live, nothing when
    it is absent or already deleted. *)

val set_upload :
  Photo_id.t ->
  state:Photo.Upload_state.t ->
  drive_file_id:string option ->
  at:Ptime.t ->
  Outbox.edit
(** [update photos set upload_state = ?, drive_file_id = ?, updated_at = ? where
     id = ? and deleted_at is null], read back by [id]. One entry when the photo
    is live; nothing changed (no entry) when it is absent or deleted. *)

val in_drive : Photo.t Stmt.query
(** Live photos with [original_target = Drive], [drive_file_id is not null] and
    [upload_state] [Uploaded] or [Original_missing] (each bound through its
    codec), ordered by [id]. A prefilter only: [Herbier_photos.Health.items]
    decides which photos the Drive health check asks about. A photo of a
    soft-deleted observation is included: its original is still the user's. *)

val set_app_only : Photo_id.t -> at:Ptime.t -> Outbox.edit
(** [update photos set original_target = ?, updated_at = ? where id = ? and
     deleted_at is null and original_target = ? and upload_state in (?, ?)] with
    [App_only], then [Drive], [Pending] and [Failed] bound through their codecs,
    read back by [id]. One entry when it changed the row; none for a photo
    absent, deleted, app-only already, [Uploaded] or [Original_missing] (an
    original already in Drive stays there). *)
