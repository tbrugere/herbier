module Organ = Herbier_identify.Organ
module Plantnet = Herbier_identify.Plantnet

let kicker : Caller.t -> string = function
  | Noter | Free_name _ -> "Pl@ntNet"
  | Queue {index; total} -> Printf.sprintf "À identifier · %d / %d" index total

let title = "Identification"
let back_label = "Retour"
let sending = "Envoi à Pl@ntNet\u{2026}"

let not_kept ~photos =
  match photos > 1 with
  | true -> "Pl@ntNet ne conserve pas les photos."
  | false -> "Pl@ntNet ne conserve pas la photo."

let skeleton_label = "Pl@ntNet\u{2026}"
let continue_ = "Continuer sans attendre"

let proposals_label (caller : Caller.t) ~count =
  let label =
    match caller with
    | Queue _ -> "Propositions Pl@ntNet"
    | Noter | Free_name _ -> "Propositions"
  in
  match count with None -> label | Some n -> Printf.sprintf "%s · %d" label n

let flora_label = Identify_settings.flora_detail

let percent score =
  match score > 0. with
  | false -> "0 %"
  | true -> (
      match Float.min 100. (Float.round (score *. 100.)) with
      | 0. -> "< 1 %"
      | p -> Printf.sprintf "%.0f %%" p)

let bar_width score =
  let clamped =
    match score > 0. with false -> 0. | true -> Float.min 1. score
  in
  let tenths = Float.round (clamped *. 1000.) in
  match Float.rem tenths 10. with
  | 0. -> Printf.sprintf "%.0f%%" (tenths /. 10.)
  | _ -> Printf.sprintf "%.1f%%" (tenths /. 10.)

let common_names (p : Plantnet.proposal) =
  match p.common_names with
  | [] -> None
  | names -> Some (String.concat " · " names)

let organ_badge = function Some o -> Organ.label o ^ " ▾" | None -> "organe ▾"

let tile_organ = Option.map Organ.label

let add_word : Organ.suggestion -> string = function
  | Add o -> Organ.label o
  | Add_photo -> "photo"

let add_hint : Organ.suggestion -> string =
  let ending = " en plus départage les espèces proches." in
  function
  | Add Flower -> "Une fleur" ^ ending
  | Add Leaf -> "Une feuille" ^ ending
  | Add Fruit -> "Un fruit" ^ ending
  | Add Bark -> "L'écorce" ^ ending
  | Add Habit -> "Le port" ^ ending
  | Add_photo -> "Une photo" ^ ending

let owned ({plant; observations} : Owned.t) =
  Printf.sprintf "Dans ma collection · %s · %d obs." plant.display_name
    observations

let action : Caller.action -> string = function
  | Choose -> "Choisir"
  | Link -> "Lier"
  | Create -> "+ Créer"

let none_matches = "Aucune ne correspond"
let organ_menu_label = "Organe de la photo"
let flora_menu_label = "Flore Pl@ntNet"

let failure_title : Failure.t -> string = function
  | No_plant _ -> "Aucune plante reconnue"
  | Not_answered -> "Pl@ntNet n'a pas répondu"
  | Offline -> "Hors-ligne"
  | Used_up -> "Quota du jour atteint"
  | Key_refused -> "Clé API refusée"
  | No_key -> "Aucune clé API"
  | Unreadable -> "Photo illisible"

let failure_body ~photos : Failure.t -> string = function
  | No_plant _ -> (
      match photos > 1 with
      | true -> "Pas de plante détectée sur ces photos."
      | false -> "Pas de plante détectée sur cette photo.")
  | Not_answered -> "Réessayez dans un moment."
  | Offline -> "Rien n'a été envoyé : réessayez avec le réseau."
  | Used_up ->
      Printf.sprintf
        "Les %d identifications Pl@ntNet du jour sont utilisées : réessayez \
         demain."
        Herbier_identify.Plantnet.daily_quota
  | Key_refused -> "Pl@ntNet a refusé la clé : vérifiez-la dans Réglages."
  | No_key -> Identify_settings.no_key_line
  | Unreadable ->
      "Une photo n'a pas pu être lue sur le téléphone : rien n'a été envoyé."

let retry = "Réessayer"
let force = "Voir quand même les propositions peu probables"
let retake = "Reprendre la photo"

let keep_unnamed ~photos =
  match photos > 1 with
  | true -> "Garder les photos, sans nom"
  | false -> "Garder la photo, sans nom"

let reask_blocked : Identify_settings.gate -> string option = function
  | Ready (_ : Identify_settings.Key.t) | Waiting -> None
  | Offline -> Some "Hors-ligne : rien ne peut être envoyé à Pl@ntNet."
  | No_key -> Some Identify_settings.no_key_line

let tile_label (p : Plantnet.proposal) (image : Plantnet.image) ~more =
  let what =
    match more > 0 with
    | true -> (
        match more with
        | 1 -> Some "1 photo de plus"
        | n -> Some (Printf.sprintf "%d photos de plus" n))
    | false -> Option.map Organ.label image.organ
  in
  match what with
  | Some w -> Printf.sprintf "Comparer : %s, %s" p.name w
  | None -> "Comparer : " ^ p.name

let compare_close = "Fermer la comparaison"

let compare_position ~index ~count =
  Printf.sprintf "Proposition %d / %d" index count

let with_organ prefix = function
  | Some o -> prefix ^ " · " ^ Organ.label o
  | None -> prefix

let compare_mine = with_organ "Ma photo"
let compare_species = with_organ "Pl@ntNet"
let compare_image_position ~index ~count = Printf.sprintf "%d / %d" index count

let compare_names (p : Plantnet.proposal) =
  match List.filter_map Fun.id [List.nth_opt p.common_names 0; p.family] with
  | [] -> None
  | parts -> Some (String.concat " · " parts)

let compare_owned ({plant; observations = (_ : int)} : Owned.t) =
  "Dans ma collection · " ^ plant.display_name

let compare_action : Caller.action -> string = function
  | Choose -> "Choisir cette espèce"
  | (Link | Create) as a -> action a

let compare_previous = "Proposition précédente"
let compare_next = "Proposition suivante"
let compare_no_image = "Pl@ntNet n'a pas envoyé de photo de cette espèce."
