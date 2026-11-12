module Observation = Herbier_domain.Observation
module Photo = Herbier_domain.Photo
module Observation_id = Herbier_domain.Ids.Observation_id
module Plant_id = Herbier_domain.Ids.Plant_id
module Places = Herbier_domain.Places

let collapsed_height = 64.
let below_chips = 36.

let snaps ~available ~top =
  let px x = match Float.is_nan x with true -> 0. | false -> x in
  let available = px available and top = px top in
  let mid =
    Float.max (collapsed_height +. 1.) (Float.min 360. (available *. 0.5))
  in
  let high = Float.max (mid +. 1.) (available -. top -. below_chips) in
  [collapsed_height; mid; high]

let title (cluster : Places.cluster) =
  Option.value (Journal_day.place cluster.members) ~default:"Lieu"

let radius = Printf.sprintf "rayon %.0f m" Places.radius_m

let summary shown =
  let plants =
    shown
    |> List.filter_map (fun (o : Observation.t) -> o.plant_id)
    |> List.sort_uniq Plant_id.compare
  in
  let observations =
    Fr_text.plural (List.length shown) "observation" "observations"
  in
  match plants with
  | [] -> String.concat " · " [radius; observations]
  | _ :: _ ->
      String.concat " · "
        [
          radius;
          observations;
          Fr_text.plural (List.length plants) "plante" "plantes";
        ]

let collapsed ~places ~observations =
  match places with
  | 0 -> "Aucune observation sur la carte"
  | _ ->
      Fr_text.plural places "lieu" "lieux"
      ^ " · "
      ^ Fr_text.plural observations "observation" "observations"

type notice =
  | Loading
  | Read_failed
  | Search_failed
  | Position_unavailable
  | Location_denied
  | Location_off

let notice_text = function
  | Loading -> "Chargement…"
  | Read_failed -> "Lecture impossible"
  | Search_failed -> "Recherche impossible"
  | Position_unavailable -> "Position indisponible"
  | Location_denied -> "Localisation non autorisée"
  | Location_off -> "Localisation désactivée"

let position_failure = function
  | Some "OS-PLUG-GLOC-0003" -> Location_denied
  | Some ("OS-PLUG-GLOC-0007" | "OS-PLUG-GLOC-0017") -> Location_off
  | Some _ | None -> Position_unavailable

type broken = Missing_tokens of string list | Map_unavailable

let broken_text = function
  | Missing_tokens missing -> "Jetons absents : " ^ String.concat ", " missing
  | Map_unavailable -> "Carte indisponible"

let rename_value (cluster : Places.cluster) =
  match Places.label cluster.members with
  | Some (Named s) -> s
  | Some (Derived _ | Coordinates _) | None -> ""

module By_observation = Map.Make (Observation_id)

let compare_photos (a : Photo.t) (b : Photo.t) =
  match Ptime.compare a.taken_at b.taken_at with
  | 0 -> Herbier_domain.Ids.Photo_id.compare a.id b.id
  | c -> c

let photos_by_observation photos =
  let index =
    List.fold_left
      (fun index (p : Photo.t) ->
        By_observation.update p.observation_id
          (fun l -> Some (p :: Option.value l ~default:[]))
          index)
      By_observation.empty photos
    |> By_observation.map (List.sort compare_photos)
  in
  fun id -> Option.value (By_observation.find_opt id index) ~default:[]

let row_meta ~this_year ~date:((year, _, _) as date) ~photos =
  let day =
    match Int.equal year this_year with
    | true -> Fr_date.day_month date
    | false -> Fr_date.full_date date
  in
  match photos with
  | 0 -> day
  | n -> day ^ " · " ^ Fr_text.plural n "photo" "photos"
