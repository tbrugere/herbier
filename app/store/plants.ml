module Plant = Herbier_domain.Plant
module Plant_id = Herbier_domain.Ids.Plant_id
module Tag_id = Herbier_domain.Ids.Tag_id
module P = Tables.Plants
module Row = Postgrest.Row

(* Lenient: Codec.decode needs total mappers, and a damaged aliases value,
   even text that is not JSON, should cost the aliases, not the plant (style
   8.4). So aliases is not a ~json column: the row parses its text itself. *)
let strings = function
  | `List items ->
      List.filter_map (function `String s -> Some s | _ -> None) items
  | _ -> []

let aliases_of_json = function
  | `String text -> (
      match Yojson.Safe.from_string text with
      | value -> strings value
      | exception Yojson.Json_error _ -> [])
  | value -> strings value

let row =
  let open Row.Syntax in
  let+ id = Row.col P.id
  and+ display_name = Row.col P.display_name
  and+ aliases = Row.col P.aliases
  and+ scientific_name = Row.col P.scientific_name
  and+ authorship = Row.col P.authorship
  and+ gbif_key = Row.col P.gbif_key
  and+ notes = Row.col P.notes
  and+ notes_updated_at = Row.col P.notes_updated_at
  and+ cover_photo_id = Row.col P.cover_photo_id
  and+ created_at = Row.col P.created_at
  and+ updated_at = Row.col P.updated_at
  and+ deleted_at = Row.col P.deleted_at in
  {
    Plant.id;
    display_name;
    aliases = aliases_of_json aliases;
    scientific_name;
    authorship;
    gbif_key;
    notes;
    notes_updated_at;
    cover_photo_id;
    created_at;
    updated_at;
    deleted_at;
  }

let query sql params = Stmt.query ~json:[] row sql params
let order_by = "display_name collate nocase, id"

let list =
  query
    ("select * from plants where deleted_at is null order by " ^ order_by)
    []

let get id =
  query "select * from plants where id = ? and deleted_at is null"
    [Codec.param P.id id]

let with_tag tag =
  query
    ("select p.* from plants p where p.deleted_at is null and exists (select 1 \
      from plant_tags pt join tags t on t.id = pt.tag_id where pt.plant_id = \
      p.id and pt.tag_id = ? and pt.deleted_at is null and t.deleted_at is \
      null) order by "
    ^ order_by)
    [Codec.param Tables.Tags.id tag]

let upsert (p : Plant.t) =
  Stmt.upsert ~table:P.table
    [
      Stmt.col P.id p.id;
      Stmt.col P.display_name p.display_name;
      Stmt.col P.aliases (`List (List.map (fun s -> `String s) p.aliases));
      Stmt.col P.scientific_name p.scientific_name;
      Stmt.col P.authorship p.authorship;
      Stmt.col P.gbif_key p.gbif_key;
      Stmt.col P.notes p.notes;
      Stmt.col P.notes_updated_at p.notes_updated_at;
      Stmt.col P.cover_photo_id p.cover_photo_id;
      Stmt.col P.created_at p.created_at;
      Stmt.col P.updated_at p.updated_at;
      Stmt.col P.deleted_at p.deleted_at;
    ]

let soft_delete id ~at =
  Stmt.soft_delete ~table:P.table ~id:(Codec.param P.id id) ~at
