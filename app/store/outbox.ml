module Col = Postgrest.Col
module Row = Postgrest.Row

type op = Upsert
type seq = int

let seq_to_int seq = seq

type entry = {
  seq : seq;
  table_name : string;
  row_id : string;
  op : op;
  payload : Yojson.Safe.t;
  created_at : Ptime.t;
  attempts : int;
  last_error : string option;
}

(* The row's table and its decoded type are existential: an edit only needs to
   encode its own row. *)
type edit =
  | Edit : {
      table : 'table Col.table;
      stmt : Stmt.t;
      reread : 'a Stmt.query;
      row_id : 'a -> string;
      input : 'a -> ('table, [`Full]) Postgrest.Input.t;
    }
      -> edit

(* A local-only table: its columns live next to its statements (layout §2),
   not in Tables. *)
type outbox

let op_label : op Col.custom =
  Codec.text ~name:"outbox_op"
    ~to_string:(function Upsert -> "upsert")
    ~of_string:(function "upsert" -> Some Upsert | _ -> None)

let seq_column : (outbox, int, [`Mandatory]) Col.t =
  {ty = Not_Null Integer; name = "seq"}

let table_name_column : (outbox, string, [`Mandatory]) Col.t =
  {ty = Not_Null Str; name = "table_name"}

let row_id_column : (outbox, string, [`Mandatory]) Col.t =
  {ty = Not_Null Str; name = "row_id"}

let op_column : (outbox, op, [`Mandatory]) Col.t =
  {ty = Not_Null (Custom op_label); name = "op"}

let payload_column : (outbox, Yojson.Safe.t, [`Mandatory]) Col.t =
  {ty = Not_Null JSON; name = "payload_json"}

let created_at_column : (outbox, Ptime.t, [`Mandatory]) Col.t =
  {ty = Not_Null TimestampTz; name = "created_at"}

let attempts_column : (outbox, int, [`Mandatory]) Col.t =
  {ty = Not_Null Integer; name = "attempts"}

let last_error_column : (outbox, string option, [`Optional]) Col.t =
  {ty = Nullable Str; name = "last_error"}

let edit ~table ~reread ~row_id ~input stmt =
  Edit {table; stmt; reread; row_id; input}

type bare = Stmt.t

let without_entry (Edit {stmt; table = _; reread = _; row_id = _; input = _}) =
  stmt

let bare stmt = stmt
let bare_stmt bare = bare

let reread (Edit {reread; table = _; stmt = _; row_id = _; input = _}) =
  Stmt.stmt reread

(* created_at comes from SQLite's clock so that Db.edit needs no clock; '%f'
   gives milliseconds, padded to Codec.timestamp's microseconds. *)
let entry_stmt ~table_name ~row_id payload =
  {
    Stmt.sql =
      "insert into outbox (table_name, row_id, op, payload_json, created_at) \
       values (?, ?, ?, ?, strftime('%Y-%m-%dT%H:%M:%f', 'now') || '000Z')";
    params =
      [
        Codec.param table_name_column table_name;
        Codec.param row_id_column row_id;
        Codec.param op_column Upsert;
        Codec.param payload_column payload;
      ];
  }

let append (Edit {table; reread; row_id; input; stmt = _}) text =
  Result.map
    (fun v ->
      entry_stmt ~table_name:(Col.name_of_table table) ~row_id:(row_id v)
        (Postgrest.Input.to_json (input v)))
    (Stmt.decode reread text)

let entry_row =
  let open Row.Syntax in
  let+ seq = Row.col seq_column
  and+ table_name = Row.col table_name_column
  and+ row_id = Row.col row_id_column
  and+ op = Row.col op_column
  and+ payload = Row.col payload_column
  and+ created_at = Row.col created_at_column
  and+ attempts = Row.col attempts_column
  and+ last_error = Row.col last_error_column in
  {seq; table_name; row_id; op; payload; created_at; attempts; last_error}

let next ~limit =
  Stmt.query
    ~json:[Codec.json payload_column]
    entry_row
    "select * from outbox where last_error is null order by seq limit ?"
    [Codec.Int (max 0 limit)]

let parked =
  Stmt.query
    ~json:[Codec.json payload_column]
    entry_row "select * from outbox where last_error is not null order by seq"
    []

let pending_ids ~table_name =
  Stmt.query ~json:[] (Row.col row_id_column)
    "select distinct row_id from outbox where table_name = ? and last_error is \
     null order by row_id"
    [Codec.param table_name_column table_name]

type outbox_count

let count =
  Stmt.query ~json:[]
    (Row.col
       ({ty = Not_Null Integer; name = "n"} : (outbox_count, int, _) Col.t))
    "select count(*) as n from outbox" []

let delete seq =
  {
    Stmt.sql = "delete from outbox where seq = ?";
    params = [Codec.param seq_column seq];
  }

let park seq ~error =
  {
    Stmt.sql =
      "update outbox set last_error = ?, attempts = attempts + 1 where seq = ?";
    params =
      [Codec.param last_error_column (Some error); Codec.param seq_column seq];
  }
