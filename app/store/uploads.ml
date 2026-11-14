module Photo_id = Herbier_domain.Ids.Photo_id
module Col = Postgrest.Col
module Row = Postgrest.Row

type session = {url : string; created_at : Ptime.t} [@@deriving eq]

type t = {
  photo_id : Photo_id.t;
  path : string;
  mime : string;
  size_bytes : int;
  session : session option;
  attempts : int;
  last_error : string option;
  created_at : Ptime.t;
}
[@@deriving eq]

(* A local-only table: its columns live next to its queries (layout §2), not
   in Tables. *)
type uploads

let table : uploads Col.table = Col.table "uploads"

let photo_id : (uploads, Photo_id.t, [`Mandatory]) Col.t =
  {ty = Not_Null (Custom Tables.ids_photo_id); name = "photo_id"}

let path : (uploads, string, [`Mandatory]) Col.t =
  {ty = Not_Null Str; name = "path"}

let mime : (uploads, string, [`Mandatory]) Col.t =
  {ty = Not_Null Str; name = "mime"}

let size_bytes : (uploads, int, [`Mandatory]) Col.t =
  {ty = Not_Null Integer; name = "size_bytes"}

let session_url : (uploads, string option, [`Optional]) Col.t =
  {ty = Nullable Str; name = "session_url"}

let session_created_at : (uploads, Ptime.t option, [`Optional]) Col.t =
  {ty = Nullable TimestampTz; name = "session_created_at"}

let attempts : (uploads, int, [`Mandatory]) Col.t =
  {ty = Not_Null Integer; name = "attempts"}

let last_error : (uploads, string option, [`Optional]) Col.t =
  {ty = Nullable Str; name = "last_error"}

let created_at : (uploads, Ptime.t, [`Mandatory]) Col.t =
  {ty = Not_Null TimestampTz; name = "created_at"}

(* The table's check keeps the session columns both null or both set, so
   the mixed cases never reach the decoder. *)
let session_of url at =
  match (url, at) with
  | Some url, Some created_at -> Some {url; created_at}
  | Some _, None | None, Some _ | None, None -> None

let row =
  let open Row.Syntax in
  let+ photo_id = Row.col photo_id
  and+ path = Row.col path
  and+ mime = Row.col mime
  and+ size_bytes = Row.col size_bytes
  and+ url = Row.col session_url
  and+ at = Row.col session_created_at
  and+ attempts = Row.col attempts
  and+ last_error = Row.col last_error
  and+ created_at = Row.col created_at in
  {
    photo_id;
    path;
    mime;
    size_bytes;
    session = session_of url at;
    attempts;
    last_error;
    created_at;
  }

let select =
  "select photo_id, path, mime, size_bytes, session_url, session_created_at, \
   attempts, last_error, created_at from uploads"

let all = Stmt.query ~json:[] row (select ^ " order by created_at, photo_id") []

let find id =
  Stmt.query ~json:[] row
    (select ^ " where photo_id = ?")
    [Codec.param photo_id id]

let put (u : t) =
  Stmt.upsert ~conflict:[photo_id.name] ~table
    Postgrest.Input.
      {
        fields =
          [
            Mandatory (photo_id, Value u.photo_id);
            Mandatory (path, Value u.path);
            Mandatory (mime, Value u.mime);
            Mandatory (size_bytes, Value u.size_bytes);
            Optional
              ( session_url,
                Value (Option.map (fun (s : session) -> s.url) u.session) );
            Optional
              ( session_created_at,
                Value (Option.map (fun (s : session) -> s.created_at) u.session)
              );
            Mandatory (attempts, Value u.attempts);
            Optional (last_error, Value u.last_error);
            Mandatory (created_at, Value u.created_at);
          ];
      }

let remove id =
  {
    Stmt.sql = "delete from uploads where photo_id = ?";
    params = [Codec.param photo_id id];
  }
