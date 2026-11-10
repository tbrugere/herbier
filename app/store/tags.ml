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

(* No deleted_at filter: a soft delete must read back the row it deleted. *)
let reread id = query "select * from tags where id = ?" [Codec.param T.id id]

let edit id stmt =
  Outbox.edit ~table:T.table ~reread:(reread id)
    ~row_id:(fun (t : Tag.t) -> Tag_id.to_string t.id)
    ~input stmt

let upsert (t : Tag.t) = edit t.id (Stmt.upsert ~table:T.table (input t))

let soft_delete id ~at =
  edit id (Stmt.soft_delete ~table:T.table ~id:(Codec.param T.id id) ~at)

(* Conflict on the natural key, not on id: a row pulled from another install
   may carry a different id for the same pair (architecture §4). *)
let upsert_plant_tag (pt : Tag.Plant_tag.t) =
  {
    Stmt.sql =
      "insert into plant_tags (id, plant_id, tag_id, created_at, updated_at, \
       deleted_at) values (?, ?, ?, ?, ?, ?) on conflict (plant_id, tag_id) do \
       update set updated_at = excluded.updated_at, deleted_at = \
       excluded.deleted_at";
    params =
      [
        Codec.param Pt.id pt.id;
        Codec.param Pt.plant_id pt.plant_id;
        Codec.param Pt.tag_id pt.tag_id;
        Codec.param Pt.created_at pt.created_at;
        Codec.param Pt.updated_at pt.updated_at;
        Codec.param Pt.deleted_at pt.deleted_at;
      ];
  }

(* By the natural key, not the derived id: a revived or pulled link keeps
   the id it was stored with, and the payload must carry that one. *)
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
    {
      Stmt.sql =
        "update plant_tags set deleted_at = ?, updated_at = ? where plant_id = \
         ? and tag_id = ? and deleted_at is null";
      params =
        [
          Codec.param Pt.deleted_at (Some at);
          Codec.param Pt.updated_at at;
          Codec.param Pt.plant_id plant;
          Codec.param Pt.tag_id tag;
        ];
    }
