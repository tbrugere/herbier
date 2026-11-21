(* Values more than one test module of test_ui uses. *)

module Plant_id = Herbier_domain.Ids.Plant_id
module Plant = Herbier_domain.Plant
module Gbif = Herbier_refs.Sources.Gbif
module Ids = Herbier_domain.Ids

let utc y m d h mi =
  match Ptime.of_date_time ((y, m, d), ((h, mi, 0), 0)) with
  | Some t -> t
  | None -> failwith "bad date"

let base_plant : Plant.t =
  {
    id = Plant_id.fresh ();
    display_name = "Ma plante";
    aliases = ["la mauve du talus"];
    scientific_name = None;
    authorship = None;
    gbif_key = None;
    notes = "vue au bord du chemin";
    notes_updated_at = Some (utc 2026 2 1 0 0);
    cover_photo_id = Some (Herbier_domain.Ids.Photo_id.fresh ());
    created_at = utc 2026 1 1 0 0;
    updated_at = utc 2026 1 1 0 0;
    deleted_at = None;
  }

let digitalis_taxon : Gbif.Taxon.t =
  {
    key = 5414995;
    scientific_name = "Digitalis purpurea L.";
    canonical_name = Some "Digitalis purpurea";
    authorship = Some "L.";
    rank = Some "SPECIES";
    status = Some Gbif.Status.Accepted;
    accepted_key = None;
    family = Some "Plantaginaceae";
    vernacular_name = Some "Foxglove";
  }

(* Three plants (Collection_filter, Journal_filter). *)
let p1 = Plant_id.fresh ()
and p2 = Plant_id.fresh ()
and p3 = Plant_id.fresh ()

(* An observation of the plant at the epoch (Collection_filter,
   Journal_filter). *)
let plant_obs plant_id : Herbier_domain.Observation.t =
  let t = Ptime.epoch in
  {
    id = Herbier_domain.Ids.Observation_id.fresh ();
    plant_id;
    at = t;
    position = None;
    place_label = None;
    place_derived = None;
    place_detail = None;
    note = None;
    created_at = t;
    updated_at = t;
    deleted_at = None;
  }

(* An observation on 12 June 2026 that can also carry a [plant_id], for
   Map_filter's identified/unidentified cases (and Local_time's). *)
let map_obs ?(hour = 12) ?(minute = 0) ?plant ?label ?derived ?detail ?pos () :
    Herbier_domain.Observation.t =
  let t = utc 2026 6 12 hour minute in
  {
    id = Ids.Observation_id.fresh ();
    plant_id = plant;
    at = t;
    position =
      Option.map
        (fun (lat, lon) ->
          {Herbier_domain.Observation.lat; lon; accuracy_m = None})
        pos;
    place_label = label;
    place_derived = derived;
    place_detail = detail;
    note = None;
    created_at = t;
    updated_at = t;
    deleted_at = None;
  }

let plant_with ?(gbif_key = None) ?(deleted_at = None) () : Plant.t =
  {base_plant with id = Plant_id.fresh (); gbif_key; deleted_at}

let tag_id = Herbier_domain.Ids.Tag_id.fresh
let plant_id = Herbier_domain.Ids.Plant_id.fresh
