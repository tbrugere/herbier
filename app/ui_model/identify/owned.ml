module Plant = Herbier_domain.Plant
module Observation = Herbier_domain.Observation
module Plant_id = Herbier_domain.Ids.Plant_id

type t = {plant : Plant.t; observations : int} [@@deriving eq]

let has_key ~keys (p : Plant.t) =
  match (p.deleted_at, p.gbif_key) with
  | None, Some k -> List.mem k keys
  | (None | Some _), (None | Some _) -> false

let find ~current ~plants ~observations = function
  | None -> None
  | Some gbif ->
      let mine (p : Plant.t) =
        has_key ~keys:[gbif] p
        && not (Option.equal Plant_id.equal (Some p.id) current)
      in
      List.find_opt mine plants
      |> Option.map (fun (plant : Plant.t) ->
          let count n (o : Observation.t) =
            match (o.deleted_at, o.plant_id) with
            | None, Some id when Plant_id.equal id plant.id -> n + 1
            | (None | Some _), (None | Some _) -> n
          in
          {plant; observations = List.fold_left count 0 observations})
