(** The device-only [ref_images] table (architecture §2 [RefImage], §3): one
    organ image per [(plant_id, source, organ)] with its downloaded thumbnail.
    Not synced: written with {!Herbier_store_io.Db.write}, never through
    {!Herbier_store_io.Db.edit}, no outbox entry. *)

module Image = Herbier_domain.Reference.Image
module Plant_id = Herbier_domain.Ids.Plant_id

val of_plant : Plant_id.t -> Image.t Stmt.query
(** Every row of the plant, ordered by [source], then [organ] in
    [Reference.Organ.all] order (flower, leaf, fruit, habit). A stored [organ]
    or [source] that does not parse is a decode error. *)

val put : Image.t -> Stmt.t
(** [insert … on conflict (plant_id, source, organ) do update set remote_url,
     licence, attribution, thumb_path] from the record: 1 change. The caller
    ([Herbier_refs.Organ_photos.plan]) decides [thumb_path]. A plant that does
    not exist is a foreign-key error. *)

val set_thumb :
  plant:Plant_id.t ->
  source:Herbier_domain.Reference.Source.t ->
  organ:Herbier_domain.Reference.Organ.t ->
  remote_url:string ->
  path:string ->
  Stmt.t
(** [thumb_path = path] on the row of the key whose [remote_url] is still
    [remote_url]: 1 change; 0 when the row is gone or now points at another
    image (the download is stale; while the syncs of a plant do not overlap, its
    file is then not referenced). *)

val remove :
  plant:Plant_id.t ->
  source:Herbier_domain.Reference.Source.t ->
  organ:Herbier_domain.Reference.Organ.t ->
  Stmt.t
(** Deletes the row (a hard delete: the table is not synced): 1 or 0 changes. *)

val clear_thumbs : Stmt.t
(** [thumb_path = null] on every row that has one: one change per such row.
    Rows, URLs, licences and attributions are kept, so the next thumbnails sync
    of each plant downloads them again (« Libérer » of 4m). *)
