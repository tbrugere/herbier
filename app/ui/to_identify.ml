module Observation = Herbier_domain.Observation

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
