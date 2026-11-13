(* style: [scientific_name], [authorship] and [gbif_key] are three options,
   not one [taxon option], because the record mirrors the [plants] row column
   for column and the store reads it through flat [Postgrest] columns, whose
   row specs cannot fail. *)
type id = Ids.Plant_id.t [@@deriving eq]

type t = {
  id : id;
  display_name : string;
  aliases : string list;
  scientific_name : string option;
  authorship : string option;
  gbif_key : int option;
  notes : string;
  notes_updated_at : Ptime.t option;
  cover_photo_id : Ids.Photo_id.t option;
  created_at : Ptime.t;
  updated_at : Ptime.t;
  deleted_at : Ptime.t option;
}
[@@deriving eq]

let v ~id ~at display_name =
  {
    id;
    display_name;
    aliases = [];
    scientific_name = None;
    authorship = None;
    gbif_key = None;
    notes = "";
    notes_updated_at = None;
    cover_photo_id = None;
    created_at = at;
    updated_at = at;
    deleted_at = None;
  }
