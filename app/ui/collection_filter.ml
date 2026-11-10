module Plant_id = Herbier_domain.Ids.Plant_id
module Observation = Herbier_domain.Observation
module By_plant = Map.Make (Plant_id)

type counts = int By_plant.t

let counts observations =
  List.fold_left
    (fun acc (o : Observation.t) ->
      match o.plant_id with
      | None -> acc
      | Some id ->
          By_plant.update id (fun n -> Some (Option.value n ~default:0 + 1)) acc)
    By_plant.empty observations

let count counts id = Option.value (By_plant.find_opt id counts) ~default:0

let has_all_tags ~tagged id =
  List.for_all (List.exists (Plant_id.equal id)) tagged
