module Observation = Herbier_domain.Observation
module Organ = Herbier_identify.Organ

type position = {index : int; total : int; next : Observation.t option}

let position (x : Observation.t) items =
  let total = List.length items in
  let rec find i = function
    | [] -> None
    | (y : Observation.t) :: rest
      when Herbier_domain.Ids.Observation_id.equal x.id y.id ->
        let next =
          match (rest, items) with
          | n :: _, _ -> Some n
          | [], first :: _ when total > 1 -> Some first
          | [], _ -> None
        in
        Some {index = i; total; next}
    | _ :: rest -> find (i + 1) rest
  in
  find 1 items

let identify_label = Record_plan.identify_label
let or_by_name = "ou par le nom"
let sent photos = List.take Organ.max_photos photos
let identify_enabled = Record_plan.identify_enabled
let no_photo_line = "Cette observation n'a pas de photo à envoyer à Pl@ntNet."
let offline_line = "Hors-ligne : l'identification reviendra avec le réseau."

let identify_line (gate : Identify_settings.gate) ~photos =
  match (photos, gate) with
  | 0, (Ready _ | Waiting | Offline | No_key) -> Some no_photo_line
  | _, No_key -> Some Identify_settings.no_key_line
  | _, Offline -> Some offline_line
  | _, (Ready _ | Waiting) -> None

let identify_aria gate ~photos =
  match photos with
  | 0 -> identify_label ^ ", aucune photo"
  | _ -> Record_plan.identify_aria gate

let caller : position option -> Identify.Caller.t = function
  | Some {index; total; _} -> Queue (Some {index; total})
  | None -> Queue None

type after = Stay | Resolve of Herbier_identify.Plantnet.proposal
[@@deriving eq]

let after_layer : Identify.Layer.outcome -> after = function
  | Chosen p -> Resolve p
  | Left | None_matches | Retake | Keep_unnamed -> Stay
