module Col = Postgrest.Col
module Row = Postgrest.Row

(* A local-only table: its columns live next to its statements (layout §2),
   not in Tables. *)
type sync_state

let table_name_column : (sync_state, string, [`Mandatory]) Col.t =
  {ty = Not_Null Str; name = "table_name"}

let last_pulled_at_column : (sync_state, Ptime.t, [`Mandatory]) Col.t =
  {ty = Not_Null TimestampTz; name = "last_pulled_at"}

let all =
  Stmt.query ~json:[]
    (Row.pair (Row.col table_name_column) (Row.col last_pulled_at_column))
    "select table_name, last_pulled_at from sync_state order by table_name" []

let set ~table_name at =
  {
    Stmt.sql =
      "insert into sync_state (table_name, last_pulled_at) values (?, ?) on \
       conflict (table_name) do update set last_pulled_at = \
       excluded.last_pulled_at";
    params =
      [
        Codec.param table_name_column table_name;
        Codec.param last_pulled_at_column at;
      ];
  }

let reset = {Stmt.sql = "delete from sync_state"; params = []}
