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
let max_ids = 500

let by_ids ~json ~table row ids =
  query ~json row
    (Printf.sprintf "select * from %s where id in (%s)"
       (Postgrest.Col.name_of_table table)
       (String.concat ", " (List.map (fun _ -> "?") ids)))
    (List.map (fun id -> Codec.Text id) ids)

(* Postgrest.Input's [Optional] does not tie its value's mode to the
   field's, so [`Full] still admits [Optional (_, Unspecified)]; it is
   skipped, as Input.to_json skips it, so the upsert and the outbox payload
   keep the same columns. *)
let column : type table.
    (table, [`Full]) Postgrest.Input.field -> (string * Codec.param) option =
  function
  | Mandatory (c, Value v) -> Some (c.name, Codec.param c v)
  | Optional (c, Value v) -> Some (c.name, Codec.param c v)
  | Optional (_, Unspecified) -> None

let upsert ?(conflict = ["id"]) ?(keep = []) ~table
    ({fields} : (_, [`Full]) Postgrest.Input.t) =
  let columns = List.filter_map column fields in
  let names = List.map fst columns in
  let fixed name = List.exists (String.equal name) (conflict @ keep) in
  let updates =
    List.filter_map
      (fun name ->
        match fixed name with
        | true -> None
        | false -> Some (name ^ " = excluded." ^ name))
      names
  in
  {
    sql =
      Printf.sprintf "insert into %s (%s) values (%s) on conflict (%s) do %s"
        (Postgrest.Col.name_of_table table)
        (String.concat ", " names)
        (String.concat ", " (List.map (fun _ -> "?") names))
        (String.concat ", " conflict)
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
