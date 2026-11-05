module Photo = Herbier_domain.Photo
module Photo_id = Herbier_domain.Ids.Photo_id
module Observation_id = Herbier_domain.Ids.Observation_id
module Plant_id = Herbier_domain.Ids.Plant_id
module Ph = Tables.Photos
module Row = Postgrest.Row

let row =
  let open Row.Syntax in
  let+ id = Row.col Ph.id
  and+ observation_id = Row.col Ph.observation_id
  and+ taken_at = Row.col Ph.taken_at
  and+ width = Row.col Ph.width
  and+ height = Row.col Ph.height
  and+ sha256 = Row.col Ph.sha256
  and+ preview_path = Row.col Ph.preview_path
  and+ preview_bucket_key = Row.col Ph.preview_bucket_key
  and+ original_target = Row.col Ph.original_target
  and+ drive_file_id = Row.col Ph.drive_file_id
  and+ upload_state = Row.col Ph.upload_state
  and+ created_at = Row.col Ph.created_at
  and+ updated_at = Row.col Ph.updated_at
  and+ deleted_at = Row.col Ph.deleted_at in
  {
    Photo.id;
    observation_id;
    taken_at;
    width;
    height;
    sha256;
    preview_path;
    preview_bucket_key;
    original_target;
    drive_file_id;
    upload_state;
    created_at;
    updated_at;
    deleted_at;
  }

let query sql params = Stmt.query ~json:[] row sql params

let get id =
  query "select * from photos where id = ? and deleted_at is null"
    [Codec.param Ph.id id]

let of_observation observation =
  query
    "select * from photos where observation_id = ? and deleted_at is null \
     order by taken_at, id"
    [Codec.param Ph.observation_id observation]

let of_plant plant =
  query
    "select ph.* from photos ph join observations o on o.id = \
     ph.observation_id where o.plant_id = ? and o.deleted_at is null and \
     ph.deleted_at is null order by ph.taken_at desc, ph.id desc"
    [Codec.param Tables.Observations.plant_id (Some plant)]

let upsert (p : Photo.t) =
  Stmt.upsert ~table:Ph.table
    [
      Stmt.col Ph.id p.id;
      Stmt.col Ph.observation_id p.observation_id;
      Stmt.col Ph.taken_at p.taken_at;
      Stmt.col Ph.width p.width;
      Stmt.col Ph.height p.height;
      Stmt.col Ph.sha256 p.sha256;
      Stmt.col Ph.preview_path p.preview_path;
      Stmt.col Ph.preview_bucket_key p.preview_bucket_key;
      Stmt.col Ph.original_target p.original_target;
      Stmt.col Ph.drive_file_id p.drive_file_id;
      Stmt.col Ph.upload_state p.upload_state;
      Stmt.col Ph.created_at p.created_at;
      Stmt.col Ph.updated_at p.updated_at;
      Stmt.col Ph.deleted_at p.deleted_at;
    ]

let soft_delete id ~at =
  Stmt.soft_delete ~table:Ph.table ~id:(Codec.param Ph.id id) ~at
