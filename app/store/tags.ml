module Tag = Herbier_domain.Tag
module Tag_id = Herbier_domain.Ids.Tag_id
module Plant_id = Herbier_domain.Ids.Plant_id
module Plant_tag_id = Herbier_domain.Ids.Plant_tag_id
module T = Tables.Tags
module Pt = Tables.Plant_tags
module Row = Postgrest.Row

let row =
  let open Row.Syntax in
  let+ id = Row.col T.id
  and+ name = Row.col T.name
  and+ created_at = Row.col T.created_at
  and+ updated_at = Row.col T.updated_at
  and+ deleted_at = Row.col T.deleted_at in
  {Tag.id; name; created_at; updated_at; deleted_at}

let plant_tag_row =
  let open Row.Syntax in
  let+ id = Row.col Pt.id
  and+ plant_id = Row.col Pt.plant_id
  and+ tag_id = Row.col Pt.tag_id
  and+ created_at = Row.col Pt.created_at
  and+ updated_at = Row.col Pt.updated_at
  and+ deleted_at = Row.col Pt.deleted_at in
  {Tag.Plant_tag.id; plant_id; tag_id; created_at; updated_at; deleted_at}

let query sql params = Stmt.query ~json:[] row sql params

let list =
  query
    "select * from tags where deleted_at is null order by name collate nocase, \
     id"
    []

let get id =
  query "select * from tags where id = ? and deleted_at is null"
    [Codec.param T.id id]

let of_plant plant =
  query
    "select t.* from tags t join plant_tags pt on pt.tag_id = t.id where \
     pt.plant_id = ? and pt.deleted_at is null and t.deleted_at is null order \
     by t.name collate nocase, t.id"
    [Codec.param Pt.plant_id plant]

let links =
  Stmt.query ~json:[] plant_tag_row
    "select pt.* from plant_tags pt join tags t on t.id = pt.tag_id join \
     plants p on p.id = pt.plant_id where pt.deleted_at is null and \
     t.deleted_at is null and p.deleted_at is null order by pt.tag_id, \
     pt.plant_id"
    []

let input (t : Tag.t) : (T.t, [`Full]) Postgrest.Input.t =
  Postgrest.Input.
    {
      fields =
        [
          Mandatory (T.id, Value t.id);
          Mandatory (T.name, Value t.name);
          Mandatory (T.created_at, Value t.created_at);
          Mandatory (T.updated_at, Value t.updated_at);
          Optional (T.deleted_at, Value t.deleted_at);
        ];
    }

let plant_tag_input (pt : Tag.Plant_tag.t) : (Pt.t, [`Full]) Postgrest.Input.t =
  Postgrest.Input.
    {
      fields =
        [
          Mandatory (Pt.id, Value pt.id);
          Mandatory (Pt.plant_id, Value pt.plant_id);
          Mandatory (Pt.tag_id, Value pt.tag_id);
          Mandatory (Pt.created_at, Value pt.created_at);
          Mandatory (Pt.updated_at, Value pt.updated_at);
          Optional (Pt.deleted_at, Value pt.deleted_at);
        ];
    }

module Writes = By_id.Make (struct
  type table = T.t
  type id = Tag_id.t
  type row = Tag.t

  let table = T.table
  let id = T.id
  let row = row
  let id_of (t : Tag.t) = t.id
  let id_to_string = Tag_id.to_string
  let input = input
end)

let upsert = Writes.upsert
let soft_delete = Writes.soft_delete

let upsert_plant_tag pt =
  Outbox.bare
    (Stmt.upsert
       ~conflict:[Pt.plant_id.name; Pt.tag_id.name]
       ~keep:[Pt.id.name; Pt.created_at.name]
       ~table:Pt.table (plant_tag_input pt))

(* By the natural key, the unique constraint the write conflicts on; the id
   is derived from it (architecture §4), so both name one row. *)
let plant_tag_edit ~plant ~tag stmt =
  Outbox.edit ~table:Pt.table
    ~reread:
      (Stmt.query ~json:[] plant_tag_row
         "select * from plant_tags where plant_id = ? and tag_id = ?"
         [Codec.param Pt.plant_id plant; Codec.param Pt.tag_id tag])
    ~row_id:(fun (pt : Tag.Plant_tag.t) -> Plant_tag_id.to_string pt.id)
    ~input:plant_tag_input stmt

(* The where clause of the update leaves a live link alone, so tagging twice
   leaves updated_at alone and appends no entry. *)
let tag ~plant ~tag ~at =
  plant_tag_edit ~plant ~tag
    {
      Stmt.sql =
        "insert into plant_tags (id, plant_id, tag_id, created_at, updated_at, \
         deleted_at) values (?, ?, ?, ?, ?, null) on conflict (plant_id, \
         tag_id) do update set deleted_at = null, updated_at = \
         excluded.updated_at where plant_tags.deleted_at is not null";
      params =
        [
          Codec.param Pt.id (Plant_tag_id.of_key ~plant ~tag);
          Codec.param Pt.plant_id plant;
          Codec.param Pt.tag_id tag;
          Codec.param Pt.created_at at;
          Codec.param Pt.updated_at at;
        ];
    }

let untag ~plant ~tag ~at =
  plant_tag_edit ~plant ~tag
    (Stmt.soft_delete_by ~table:Pt.table
       ~key:(Is (Pt.plant_id, plant), [Is (Pt.tag_id, tag)])
       ~at)
