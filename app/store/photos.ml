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

let input (p : Photo.t) : (Ph.t, [`Full]) Postgrest.Input.t =
  Postgrest.Input.
    {
      fields =
        [
          Mandatory (Ph.id, Value p.id);
          Mandatory (Ph.observation_id, Value p.observation_id);
          Mandatory (Ph.taken_at, Value p.taken_at);
          Mandatory (Ph.width, Value p.width);
          Mandatory (Ph.height, Value p.height);
          Mandatory (Ph.sha256, Value p.sha256);
          Mandatory (Ph.preview_path, Value p.preview_path);
          Optional (Ph.preview_bucket_key, Value p.preview_bucket_key);
          Mandatory (Ph.original_target, Value p.original_target);
          Optional (Ph.drive_file_id, Value p.drive_file_id);
          Mandatory (Ph.upload_state, Value p.upload_state);
          Mandatory (Ph.created_at, Value p.created_at);
          Mandatory (Ph.updated_at, Value p.updated_at);
          Optional (Ph.deleted_at, Value p.deleted_at);
        ];
    }

(* No deleted_at filter: a soft delete must read back the row it deleted. *)
let reread id = query "select * from photos where id = ?" [Codec.param Ph.id id]

let edit id stmt =
  Outbox.edit ~table:Ph.table ~reread:(reread id)
    ~row_id:(fun (p : Photo.t) -> Photo_id.to_string p.id)
    ~input stmt

let upsert (p : Photo.t) = edit p.id (Stmt.upsert ~table:Ph.table (input p))

let soft_delete id ~at =
  edit id (Stmt.soft_delete ~table:Ph.table ~id:(Codec.param Ph.id id) ~at)
