module Photo_id = Herbier_domain.Ids.Photo_id
module Col = Postgrest.Col
module Row = Postgrest.Row

type t = {
  photo_id : Photo_id.t;
  file_id : string;
  attempts : int;
  last_error : string option;
  created_at : Ptime.t;
}
[@@deriving eq]

(* A local-only table: its columns live next to its queries (layout §2), not
   in Tables. *)
type drive_trash

let table : drive_trash Col.table = Col.table "drive_trash"

let photo_id : (drive_trash, Photo_id.t, [`Mandatory]) Col.t =
  {ty = Not_Null (Custom Tables.ids_photo_id); name = "photo_id"}

let file_id : (drive_trash, string, [`Mandatory]) Col.t =
  {ty = Not_Null Str; name = "file_id"}

let attempts : (drive_trash, int, [`Mandatory]) Col.t =
  {ty = Not_Null Integer; name = "attempts"}

let last_error : (drive_trash, string option, [`Optional]) Col.t =
  {ty = Nullable Str; name = "last_error"}

let created_at : (drive_trash, Ptime.t, [`Mandatory]) Col.t =
  {ty = Not_Null TimestampTz; name = "created_at"}

let row =
  let open Row.Syntax in
  let+ photo_id = Row.col photo_id
  and+ file_id = Row.col file_id
  and+ attempts = Row.col attempts
  and+ last_error = Row.col last_error
  and+ created_at = Row.col created_at in
  {photo_id; file_id; attempts; last_error; created_at}

let all =
  Stmt.query ~json:[] row
    "select photo_id, file_id, attempts, last_error, created_at from \
     drive_trash order by created_at, photo_id"
    []

let add id ~file_id:f ~at =
  {
    Stmt.sql =
      "insert into drive_trash (photo_id, file_id, attempts, last_error, \
       created_at) values (?, ?, 0, null, ?) on conflict (photo_id) do nothing";
    params =
      [
        Codec.param photo_id id; Codec.param file_id f; Codec.param created_at at;
      ];
  }

let put (r : t) =
  Stmt.upsert ~conflict:[photo_id.name] ~table
    Postgrest.Input.
      {
        fields =
          [
            Mandatory (photo_id, Value r.photo_id);
            Mandatory (file_id, Value r.file_id);
            Mandatory (attempts, Value r.attempts);
            Optional (last_error, Value r.last_error);
            Mandatory (created_at, Value r.created_at);
          ];
      }

let remove id =
  {
    Stmt.sql = "delete from drive_trash where photo_id = ?";
    params = [Codec.param photo_id id];
  }
