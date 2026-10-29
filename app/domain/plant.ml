(* style: [scientific_name], [authorship] and [gbif_key] are three options,
   not one [taxon option], because the record mirrors the [plants] row column
   for column and the store reads it through flat [Postgrest] columns, whose
   row specs cannot fail. *)
type id = Ids.Plant_id.t

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
