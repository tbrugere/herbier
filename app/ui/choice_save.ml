module Observations = Herbier_store.Observations
module Plants = Herbier_store.Plants
module Observation = Herbier_domain.Observation
module Observation_plan = Herbier_ui_model.Observation_plan

let onto ~at (o : Observation.t) plant =
  Observations.upsert {o with plant_id = Some plant; updated_at = at}

let save app ~at o : Observation_plan.write -> _ =
  let saved edits =
    Fut.map (Result.map (fun (_ : int) -> ())) (App.save app edits)
  in
  function
  | Attach id -> saved [onto ~at o id]
  | Create_free p -> saved [Plants.upsert p; onto ~at o p.id]
  | Create_linked {plant; taxon} ->
      App.create_linked app ~extra:[onto ~at o plant.id] plant taxon
