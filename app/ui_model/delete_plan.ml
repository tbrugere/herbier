module Ids = Herbier_domain.Ids
module Cascade = Herbier_store.Cascade

type plant = {
  plant : Herbier_domain.Plant.t;
  observations : Ids.Observation_id.t list;
  photos : Ids.Photo_id.t list;
  tags : Ids.Tag_id.t list;
  in_drive : int;
}

type observation = {
  observation : Ids.Observation_id.t;
  photos : Ids.Photo_id.t list;
  in_drive : int;
}

let photo_ids = List.map (fun (p : Herbier_domain.Photo.t) -> p.id)

let has_drive_file (p : Herbier_domain.Photo.t) =
  match (p.original_target, p.drive_file_id) with
  | Drive, Some id -> not (String.equal (String.trim id) "")
  | Drive, None | App_only, _ -> false

let count_in_drive photos = List.length (List.filter has_drive_file photos)

let plant_of plant ~observations ~photos ~tags =
  {
    plant;
    observations =
      List.map (fun (o : Herbier_domain.Observation.t) -> o.id) observations;
    photos = photo_ids photos;
    tags = List.map (fun (t : Herbier_domain.Tag.t) -> t.id) tags;
    in_drive = count_in_drive photos;
  }

let observation_of observation ~photos =
  {observation; photos = photo_ids photos; in_drive = count_in_drive photos}

(* The originals that go to Drive's bin, among [p] photos leaving. *)
let drive_sentence ~photos:p = function
  | 0 -> None
  | 1 when p = 1 ->
      Some
        "Son original va dans la corbeille de Google Drive (récupérable 30 \
         jours)."
  | d when d = p ->
      Some
        "Leurs originaux vont dans la corbeille de Google Drive (récupérables \
         30 jours)."
  | 1 ->
      Some
        "L'original déjà envoyé va dans la corbeille de Google Drive \
         (récupérable 30 jours)."
  | d ->
      Some
        (Printf.sprintf
           "Les %d originaux déjà envoyés vont dans la corbeille de Google \
            Drive (récupérables 30 jours)."
           d)

let with_drive text ~photos in_drive =
  match drive_sentence ~photos in_drive with
  | None -> text
  | Some s -> text ^ " " ^ s

type choice = Delete | Keep

let plant_title (p : Herbier_domain.Plant.t) =
  Printf.sprintf "Supprimer « %s » ?" p.display_name

let its_observations = function
  | 1 -> "son observation"
  | n -> Printf.sprintf "ses %d observations" n

let plant_text (d : plant) =
  match (List.length d.observations, List.length d.photos) with
  | 0, _ -> "La fiche quitte l'herbier."
  | n, 0 ->
      Printf.sprintf "La fiche et %s quittent l'herbier." (its_observations n)
  | n, p ->
      with_drive ~photos:p
        (Printf.sprintf "La fiche, %s et %s %s quittent l'herbier."
           (its_observations n)
           (match n with 1 -> "ses" | _ -> "leurs")
           (Fr_text.plural p "photo" "photos"))
        d.in_drive

let plant_action (d : plant) =
  match List.length d.observations with
  | 0 -> "Supprimer la plante ›"
  | n -> Printf.sprintf "Supprimer la plante et %s ›" (its_observations n)

let plant_failure = "La plante n'a pas pu être supprimée."

let plant_edits ~at (d : plant) =
  Cascade.plant ~at ~photos:d.photos ~observations:d.observations ~tags:d.tags
    d.plant.id

let observation_title = "Supprimer cette observation ?"

let observation_text (d : observation) =
  match List.length d.photos with
  | 0 -> "Elle quitte l'herbier et le journal."
  | n ->
      with_drive ~photos:n
        (Printf.sprintf "Elle quitte l'herbier avec ses %s."
           (Fr_text.plural n "photo" "photos"))
        d.in_drive

let observation_failure = "L'observation n'a pas pu être supprimée."

let observation_edits ~at (d : observation) =
  Cascade.observation ~at ~photos:d.photos d.observation

let photo_title = "Retirer cette photo d'Herbier ?"

let photo_text ~in_drive =
  with_drive ~photos:1 "Elle quitte la fiche et l'observation."
    (match in_drive with true -> 1 | false -> 0)
