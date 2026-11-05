module Plant = Herbier_domain.Plant
module Plant_id = Herbier_domain.Ids.Plant_id
module Tag_id = Herbier_domain.Ids.Tag_id
module P = Tables.Plants
module Row = Postgrest.Row

(* Lenient: Codec.decode needs total mappers, and a damaged aliases value,
   even text that is not JSON, should cost the aliases, not the plant (style
   8.4). So aliases is not a ~json column: the row parses its text itself.
   The outbox payload is built from the decoded row, so a damaged value is
   pushed as [] on the plant's next edit. *)
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

let input (p : Plant.t) : (P.t, [`Full]) Postgrest.Input.t =
  Postgrest.Input.
    {
      fields =
        [
          Mandatory (P.id, Value p.id);
          Mandatory (P.display_name, Value p.display_name);
          Mandatory
            (P.aliases, Value (`List (List.map (fun s -> `String s) p.aliases)));
          Optional (P.scientific_name, Value p.scientific_name);
          Optional (P.authorship, Value p.authorship);
          Optional (P.gbif_key, Value p.gbif_key);
          Mandatory (P.notes, Value p.notes);
          Optional (P.notes_updated_at, Value p.notes_updated_at);
          Optional (P.cover_photo_id, Value p.cover_photo_id);
          Mandatory (P.created_at, Value p.created_at);
          Mandatory (P.updated_at, Value p.updated_at);
          Optional (P.deleted_at, Value p.deleted_at);
        ];
    }

(* No deleted_at filter: a soft delete must read back the row it deleted. *)
let reread id = query "select * from plants where id = ?" [Codec.param P.id id]

let edit id stmt =
  Outbox.edit ~table:P.table ~reread:(reread id)
    ~row_id:(fun (p : Plant.t) -> Plant_id.to_string p.id)
    ~input stmt

let upsert (p : Plant.t) = edit p.id (Stmt.upsert ~table:P.table (input p))

let soft_delete id ~at =
  edit id (Stmt.soft_delete ~table:P.table ~id:(Codec.param P.id id) ~at)
