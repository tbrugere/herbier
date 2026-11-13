(* Helpers shared by test_rest and test_push_order: the mock backend, a
   connection on it, times, the fixture ids and one row builder per synced
   table (optional fields unset, every instant [at]). *)

module Ids = Herbier_domain.Ids
module Plant = Herbier_domain.Plant
module Observation = Herbier_domain.Observation
module Photo = Herbier_domain.Photo
module Tag = Herbier_domain.Tag
module Reference = Herbier_domain.Reference

module H = struct
  include Mock_http

  let error_to_string = Fun.id
end

module R = Rest.Make (H)

let conn =
  Rest.conn ~supabase_url:"http://127.0.0.1:54321" ~apikey:"K" ~token:"T"

let time s =
  match Ptime.of_rfc3339 s with
  | Ok (t, _, _) -> t
  | Error _ -> invalid_arg ("fixture time " ^ s)

(* The ids scripts/record-sync-fixtures.sh writes (UUID v7 shape). *)
let uuid n = Printf.sprintf "01965d4e-0000-7000-8000-%012x" n

let id_of what of_string n =
  match of_string (uuid n) with
  | Some x -> x
  | None -> invalid_arg ("fixture " ^ what)

let plant_id = id_of "plant id" Ids.Plant_id.of_string
let observation_id = id_of "observation id" Ids.Observation_id.of_string
let photo_id = id_of "photo id" Ids.Photo_id.of_string
let tag_id = id_of "tag id" Ids.Tag_id.of_string
let plant_tag_id = id_of "plant tag id" Ids.Plant_tag_id.of_string
let plant_ref_id = id_of "plant ref id" Ids.Plant_ref_id.of_string
let reference_id = id_of "reference id" Ids.Reference_id.of_string

let plant ~at n display_name : Plant.t =
  {
    id = plant_id n;
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

let tag ~at n name : Tag.t =
  {id = tag_id n; name; created_at = at; updated_at = at; deleted_at = None}

let observation ~at ?plant n : Observation.t =
  {
    id = observation_id n;
    plant_id = Option.map plant_id plant;
    at;
    position = None;
    place_label = None;
    place_derived = None;
    note = None;
    created_at = at;
    updated_at = at;
    deleted_at = None;
  }

let photo ~at ~observation n : Photo.t =
  {
    id = photo_id n;
    observation_id = observation_id observation;
    taken_at = at;
    width = 1;
    height = 1;
    sha256 = String.make 64 'a';
    preview_path = Printf.sprintf "previews/%d.webp" n;
    preview_bucket_key = None;
    original_target = Photo.Original_target.App_only;
    drive_file_id = None;
    upload_state = Photo.Upload_state.Pending;
    created_at = at;
    updated_at = at;
    deleted_at = None;
  }

let plant_tag ~at ~plant ~tag n : Tag.Plant_tag.t =
  {
    id = plant_tag_id n;
    plant_id = plant_id plant;
    tag_id = tag_id tag;
    created_at = at;
    updated_at = at;
    deleted_at = None;
  }

(* external_id is [n], as a GBIF species key. *)
let plant_ref ~at ~plant n : Reference.Plant_ref.t =
  {
    id = plant_ref_id n;
    plant_id = plant_id plant;
    source = Reference.Source.Gbif;
    external_id = Int.to_string n;
    url = Printf.sprintf "https://www.gbif.org/species/%d" n;
    created_at = at;
    updated_at = at;
    deleted_at = None;
  }

let reference ~at ~plant n : Reference.t =
  {
    id = reference_id n;
    plant_id = plant_id plant;
    source = Reference.Source.Gbif;
    fetched_at = at;
    payload = `Assoc [];
    status = Reference.Status.Complete;
    created_at = at;
    updated_at = at;
    deleted_at = None;
  }
