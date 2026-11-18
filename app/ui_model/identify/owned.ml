module Plant = Herbier_domain.Plant
module Observation = Herbier_domain.Observation
module Plant_id = Herbier_domain.Ids.Plant_id

type t = {plant : Plant.t; observations : int} [@@deriving eq]

let find ~current ~plants ~observations = function
  | None -> None
  | Some gbif ->
      let mine (p : Plant.t) =
        Option.is_none p.deleted_at
        && Option.equal Int.equal p.gbif_key (Some gbif)
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
