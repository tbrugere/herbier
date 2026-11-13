module type TABLE = sig
  type table
  type id
  type row

  val table : table Postgrest.Col.table
  val id : (table, id, [`Mandatory]) Postgrest.Col.t
  val row : (table, row) Postgrest.Row.t
  val id_of : row -> id
  val id_to_string : id -> string
  val input : row -> (table, [`Full]) Postgrest.Input.t
end

module Make (T : TABLE) = struct
  let reread id =
    Stmt.query ~json:[] T.row
      (Printf.sprintf "select * from %s where id = ?"
         (Postgrest.Col.name_of_table T.table))
      [Codec.param T.id id]

  let edit id stmt =
    Outbox.edit ~table:T.table ~reread:(reread id)
      ~row_id:(fun row -> T.id_to_string (T.id_of row))
      ~input:T.input stmt

  let upsert row = edit (T.id_of row) (Stmt.upsert ~table:T.table (T.input row))

  let soft_delete id ~at =
    edit id (Stmt.soft_delete ~table:T.table ~id:(Codec.param T.id id) ~at)
end
