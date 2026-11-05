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

let upsert (t : Tag.t) =
  Stmt.upsert ~table:T.table
    [
      Stmt.col T.id t.id;
      Stmt.col T.name t.name;
      Stmt.col T.created_at t.created_at;
      Stmt.col T.updated_at t.updated_at;
      Stmt.col T.deleted_at t.deleted_at;
    ]

let soft_delete id ~at =
  Stmt.soft_delete ~table:T.table ~id:(Codec.param T.id id) ~at

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

(* The where clause of the update leaves a live link alone, so tagging twice
   leaves updated_at alone. *)
let tag ~plant ~tag ~at =
  {
    Stmt.sql =
      "insert into plant_tags (id, plant_id, tag_id, created_at, updated_at, \
       deleted_at) values (?, ?, ?, ?, ?, null) on conflict (plant_id, tag_id) \
       do update set deleted_at = null, updated_at = excluded.updated_at where \
       plant_tags.deleted_at is not null";
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
  {
    Stmt.sql =
      "update plant_tags set deleted_at = ?, updated_at = ? where plant_id = ? \
       and tag_id = ? and deleted_at is null";
    params =
      [
        Codec.param Pt.deleted_at (Some at);
        Codec.param Pt.updated_at at;
        Codec.param Pt.plant_id plant;
        Codec.param Pt.tag_id tag;
      ];
  }
