module Ids = Herbier_domain.Ids
module Cascade = Herbier_store.Cascade

type plant = {
  plant : Herbier_domain.Plant.t;
  observations : Ids.Observation_id.t list;
  photos : Ids.Photo_id.t list;
  tags : Ids.Tag_id.t list;
}

type observation = {
  observation : Ids.Observation_id.t;
  photos : Ids.Photo_id.t list;
}

let photo_ids = List.map (fun (p : Herbier_domain.Photo.t) -> p.id)

let plant_of plant ~observations ~photos ~tags =
  {
    plant;
    observations =
      List.map (fun (o : Herbier_domain.Observation.t) -> o.id) observations;
    photos = photo_ids photos;
    tags = List.map (fun (t : Herbier_domain.Tag.t) -> t.id) tags;
  }

let observation_of observation ~photos =
  {observation; photos = photo_ids photos}

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
      Printf.sprintf
        "La fiche, %s et %s %s quittent l'herbier. Les originaux envoyés dans \
         Google Drive y restent."
        (its_observations n)
        (match n with 1 -> "ses" | _ -> "leurs")
        (Fr_text.plural p "photo" "photos")

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
      Printf.sprintf
        "Elle quitte l'herbier avec ses %s. Les originaux envoyés dans Google \
         Drive y restent."
        (Fr_text.plural n "photo" "photos")

let observation_failure = "L'observation n'a pas pu être supprimée."

let observation_edits ~at (d : observation) =
  Cascade.observation ~at ~photos:d.photos d.observation
