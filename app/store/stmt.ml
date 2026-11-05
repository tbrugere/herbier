type t = {sql : string; params : Codec.param list}

(* The table type is existential: a query only needs to decode its own rows. *)
type 'a query =
  | Query : {
      stmt : t;
      json : 'table Codec.json_column list;
      row : ('table, 'a) Postgrest.Row.t;
    }
      -> 'a query

let query ~json row sql params = Query {stmt = {sql; params}; json; row}
let stmt (Query {stmt; json = _; row = _}) = stmt
let decode (Query {stmt = _; json; row}) text = Codec.decode ~json row text
let col (c : (_, _, _) Postgrest.Col.t) v = (c.name, Codec.param c v)

let upsert ~table columns =
  let names = List.map fst columns in
  let updates =
    List.filter_map
      (function "id" -> None | name -> Some (name ^ " = excluded." ^ name))
      names
  in
  {
    sql =
      Printf.sprintf "insert into %s (%s) values (%s) on conflict (id) do %s"
        (Postgrest.Col.name_of_table table)
        (String.concat ", " names)
        (String.concat ", " (List.map (fun _ -> "?") names))
        (match updates with
        | [] -> "nothing"
        | _ :: _ -> "update set " ^ String.concat ", " updates);
    params = List.map snd columns;
  }

let soft_delete ~table ~id ~at =
  let at = Codec.Text (Codec.timestamp at) in
  {
    sql =
      Printf.sprintf
        "update %s set deleted_at = ?, updated_at = ? where id = ? and \
         deleted_at is null"
        (Postgrest.Col.name_of_table table);
    params = [at; at; id];
  }
