module Col = Postgrest.Col
module Row = Postgrest.Row

type t = {
  departement : string;
  name : string;
  path : string;
  size_bytes : int;
  communes : int;
  downloaded_at : Ptime.t;
}
[@@deriving eq]

(* A local-only table: its columns live next to its queries (layout §2), not
   in Tables. *)
type commune_packs

let table : commune_packs Col.table = Col.table "commune_packs"

let departement : (commune_packs, string, [`Mandatory]) Col.t =
  {ty = Not_Null Str; name = "departement"}

let name : (commune_packs, string, [`Mandatory]) Col.t =
  {ty = Not_Null Str; name = "name"}

let path : (commune_packs, string, [`Mandatory]) Col.t =
  {ty = Not_Null Str; name = "path"}

let size_bytes : (commune_packs, int, [`Mandatory]) Col.t =
  {ty = Not_Null Integer; name = "size_bytes"}

let communes : (commune_packs, int, [`Mandatory]) Col.t =
  {ty = Not_Null Integer; name = "communes"}

let downloaded_at : (commune_packs, Ptime.t, [`Mandatory]) Col.t =
  {ty = Not_Null TimestampTz; name = "downloaded_at"}

let row =
  let open Row.Syntax in
  let+ departement = Row.col departement
  and+ name = Row.col name
  and+ path = Row.col path
  and+ size_bytes = Row.col size_bytes
  and+ communes = Row.col communes
  and+ downloaded_at = Row.col downloaded_at in
  {departement; name; path; size_bytes; communes; downloaded_at}

let select =
  "select departement, name, path, size_bytes, communes, downloaded_at from \
   commune_packs"

let all = Stmt.query ~json:[] row (select ^ " order by departement") []

let find code =
  Stmt.query ~json:[] row
    (select ^ " where departement = ?")
    [Codec.param departement code]

let put (p : t) =
  Stmt.upsert ~conflict:[departement.name] ~table
    Postgrest.Input.
      {
        fields =
          [
            Mandatory (departement, Value p.departement);
            Mandatory (name, Value p.name);
            Mandatory (path, Value p.path);
            Mandatory (size_bytes, Value p.size_bytes);
            Mandatory (communes, Value p.communes);
            Mandatory (downloaded_at, Value p.downloaded_at);
          ];
      }

let remove ~departement:code =
  {
    Stmt.sql = "delete from commune_packs where departement = ?";
    params = [Codec.param departement code];
  }
