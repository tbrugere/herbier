module Store = Herbier_store
module Tables = Store.Tables
module D = Herbier_domain
module Row = Postgrest.Row

type ('table, 'row) t = {
  table : 'table Postgrest.Col.table;
  row : ('table, 'row) Row.t;
  input : 'row -> ('table, [`Full]) Postgrest.Input.t;
  updated_at_col : ('table, Ptime.t, [`Mandatory]) Postgrest.Col.t;
  order_id : ('table, string) Row.t;
  equal : 'row -> 'row -> bool;
  id : 'row -> string;
  updated_at : 'row -> Ptime.t;
  json : 'table Store.Codec.json_column list;
  write : 'row -> Store.Outbox.bare;
}

type any = Any : ('table, 'row) t -> any

let id_text to_string col = Row.map to_string (Row.col col)

let plants =
  {
    table = Tables.Plants.table;
    row = Store.Plants.row;
    input = Store.Plants.input;
    updated_at_col = Tables.Plants.updated_at;
    order_id = id_text D.Ids.Plant_id.to_string Tables.Plants.id;
    equal = D.Plant.equal;
    id = (fun r -> D.Ids.Plant_id.to_string r.D.Plant.id);
    updated_at = (fun r -> r.D.Plant.updated_at);
    json = [];
    write = (fun r -> Store.Outbox.without_entry (Store.Plants.upsert r));
  }

let tags =
  {
    table = Tables.Tags.table;
    row = Store.Tags.row;
    input = Store.Tags.input;
    updated_at_col = Tables.Tags.updated_at;
    order_id = id_text D.Ids.Tag_id.to_string Tables.Tags.id;
    equal = D.Tag.equal;
    id = (fun r -> D.Ids.Tag_id.to_string r.D.Tag.id);
    updated_at = (fun r -> r.D.Tag.updated_at);
    json = [];
    write = (fun r -> Store.Outbox.without_entry (Store.Tags.upsert r));
  }

let observations =
  {
    table = Tables.Observations.table;
    row = Store.Observations.row;
    input = Store.Observations.input;
    updated_at_col = Tables.Observations.updated_at;
    order_id = id_text D.Ids.Observation_id.to_string Tables.Observations.id;
    equal = D.Observation.equal;
    id = (fun r -> D.Ids.Observation_id.to_string r.D.Observation.id);
    updated_at = (fun r -> r.D.Observation.updated_at);
    json = [];
    write = (fun r -> Store.Outbox.without_entry (Store.Observations.upsert r));
  }

let photos =
  {
    table = Tables.Photos.table;
    row = Store.Photos.row;
    input = Store.Photos.input;
    updated_at_col = Tables.Photos.updated_at;
    order_id = id_text D.Ids.Photo_id.to_string Tables.Photos.id;
    equal = D.Photo.equal;
    id = (fun r -> D.Ids.Photo_id.to_string r.D.Photo.id);
    updated_at = (fun r -> r.D.Photo.updated_at);
    json = [];
    write = (fun r -> Store.Outbox.without_entry (Store.Photos.upsert r));
  }

let plant_tags =
  {
    table = Tables.Plant_tags.table;
    row = Store.Tags.plant_tag_row;
    input = Store.Tags.plant_tag_input;
    updated_at_col = Tables.Plant_tags.updated_at;
    order_id = id_text D.Ids.Plant_tag_id.to_string Tables.Plant_tags.id;
    equal = D.Tag.Plant_tag.equal;
    id = (fun r -> D.Ids.Plant_tag_id.to_string r.D.Tag.Plant_tag.id);
    updated_at = (fun r -> r.D.Tag.Plant_tag.updated_at);
    json = [];
    write = Store.Tags.upsert_plant_tag;
  }

let plant_refs =
  {
    table = Tables.Plant_refs.table;
    row = Store.References.plant_ref_row;
    input = Store.References.plant_ref_input;
    updated_at_col = Tables.Plant_refs.updated_at;
    order_id = id_text D.Ids.Plant_ref_id.to_string Tables.Plant_refs.id;
    equal = D.Reference.Plant_ref.equal;
    id = (fun r -> D.Ids.Plant_ref_id.to_string r.D.Reference.Plant_ref.id);
    updated_at = (fun r -> r.D.Reference.Plant_ref.updated_at);
    json = [];
    write = Store.References.upsert_plant_ref;
  }

let reference =
  {
    table = Tables.Reference.table;
    row = Store.References.row;
    input = Store.References.input;
    updated_at_col = Tables.Reference.updated_at;
    order_id = id_text D.Ids.Reference_id.to_string Tables.Reference.id;
    equal = D.Reference.equal;
    id = (fun r -> D.Ids.Reference_id.to_string r.D.Reference.id);
    updated_at = (fun r -> r.D.Reference.updated_at);
    json = Store.References.json;
    write = Store.References.upsert_row;
  }

let all =
  [
    Any plants;
    Any tags;
    Any observations;
    Any photos;
    Any plant_tags;
    Any plant_refs;
    Any reference;
  ]

let table t = t.table
let row t = t.row
let input t = t.input
let updated_at_col t = t.updated_at_col
let name t = Postgrest.Col.name_of_table t.table
let of_name s = List.find_opt (fun (Any t) -> String.equal (name t) s) all
let order t = Row.pair (Row.col t.updated_at_col) t.order_id
let decide t = D.Merge.decide ~equal:t.equal
let decode_payload t json = Store.Codec.decode_value t.row json

type entry = Entry : ('table, 'row) t * 'row -> entry

type entry_error =
  | Unknown_table of string
  | Bad_payload of string * Postgrest.Row.error

let decode_entry ~table_name payload =
  match of_name table_name with
  | None -> Error (Unknown_table table_name)
  | Some (Any t) -> (
      match decode_payload t payload with
      | Ok row -> Ok (Entry (t, row))
      | Error e -> Error (Bad_payload (table_name, e)))

let entry_error_to_string = function
  | Unknown_table name -> "unknown table " ^ name
  | Bad_payload (name, e) ->
      Printf.sprintf "%s payload: %s" name (Store.Codec.row_error_to_string e)

let id t = t.id
let updated_at t = t.updated_at
let local t ids = Store.Stmt.by_ids ~json:t.json ~table:t.table t.row ids
let write t = t.write
