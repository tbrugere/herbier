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
  }

let tags =
  {
    table = Tables.Tags.table;
    row = Store.Tags.row;
    input = Store.Tags.input;
    updated_at_col = Tables.Tags.updated_at;
    order_id = id_text D.Ids.Tag_id.to_string Tables.Tags.id;
    equal = D.Tag.equal;
  }

let observations =
  {
    table = Tables.Observations.table;
    row = Store.Observations.row;
    input = Store.Observations.input;
    updated_at_col = Tables.Observations.updated_at;
    order_id = id_text D.Ids.Observation_id.to_string Tables.Observations.id;
    equal = D.Observation.equal;
  }

let photos =
  {
    table = Tables.Photos.table;
    row = Store.Photos.row;
    input = Store.Photos.input;
    updated_at_col = Tables.Photos.updated_at;
    order_id = id_text D.Ids.Photo_id.to_string Tables.Photos.id;
    equal = D.Photo.equal;
  }

let plant_tags =
  {
    table = Tables.Plant_tags.table;
    row = Store.Tags.plant_tag_row;
    input = Store.Tags.plant_tag_input;
    updated_at_col = Tables.Plant_tags.updated_at;
    order_id = id_text D.Ids.Plant_tag_id.to_string Tables.Plant_tags.id;
    equal = D.Tag.Plant_tag.equal;
  }

let plant_refs =
  {
    table = Tables.Plant_refs.table;
    row = Store.References.plant_ref_row;
    input = Store.References.plant_ref_input;
    updated_at_col = Tables.Plant_refs.updated_at;
    order_id = id_text D.Ids.Plant_ref_id.to_string Tables.Plant_refs.id;
    equal = D.Reference.Plant_ref.equal;
  }

let reference =
  {
    table = Tables.Reference.table;
    row = Store.References.row;
    input = Store.References.input;
    updated_at_col = Tables.Reference.updated_at;
    order_id = id_text D.Ids.Reference_id.to_string Tables.Reference.id;
    equal = D.Reference.equal;
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
