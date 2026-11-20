module Plant = Herbier_domain.Plant
module Observation = Herbier_domain.Observation
module Plant_id = Herbier_domain.Ids.Plant_id
module Taxon = Herbier_refs.Sources.Gbif.Taxon

type arrival = Opened | Recorded of {identify : bool}

let toast arrival ~layer (plant : Plant.t option) =
  match (arrival, layer, plant) with
  | Opened, (true | false), (Some _ | None) | Recorded _, true, (Some _ | None)
    ->
      None
  | Recorded _, false, Some p ->
      Some ("Enregistrée · ajoutée à " ^ p.display_name)
  | Recorded _, false, None -> Some "Enregistrée · à identifier"

let toast_ms = 2500

let identifiable (o : Observation.t) =
  match o.plant_id with None -> true | Some (_ : Plant_id.t) -> false

let identify_line (gate : Identify_settings.gate) ~photos =
  match (photos, gate) with
  | 0, (Ready _ | Waiting | Offline | No_key) -> Some To_identify.no_photo_line
  | _, Offline -> Some To_identify.offline_line
  | _, (Ready _ | Waiting | No_key) -> None

let opens_layer arrival o gate ~photos =
  match arrival with
  | Recorded {identify = true} ->
      identifiable o && To_identify.identify_enabled gate ~photos
  | Recorded {identify = false} | Opened -> false

let by_name_label = "Chercher un nom"
let map_label = "Corriger la position sur la carte"

type write =
  | Attach of Plant_id.t
  | Create_free of Plant.t
  | Create_linked of {plant : Plant.t; taxon : Taxon.t}
[@@deriving eq]

let write ~at ~new_plant : Record_plan.choice -> write option = function
  | Target (Existing p) -> Some (Attach p.id)
  | Target (Free name) -> Some (Create_free (Plant.v ~id:new_plant ~at name))
  | Linked {name; taxon} ->
      Some
        (Create_linked
           {plant = Plant_link.create ~id:new_plant ~at ~name taxon; taxon})
  | Target To_identify -> None

let chosen ~at ~new_plant ~plants c =
  write ~at ~new_plant (Record_plan.of_choice ~plants c)

let no_name = "Cette proposition n'a pas de nom."

let plant_of = function
  | Attach id -> id
  | Create_free p | Create_linked {plant = p; taxon = (_ : Taxon.t)} -> p.id
