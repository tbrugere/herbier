module Observation = Herbier_domain.Observation
module Plant_id = Herbier_domain.Ids.Plant_id
module Places = Herbier_domain.Places

type query =
  | Everything
  | Matching of {plants : Plant_id.t list; place : Places.cluster -> bool}

let place_name (cluster : Places.cluster) =
  match Places.label cluster.members with
  | Some (Named s | Derived s) -> Some s
  | Some (Coordinates _) | None -> None

let place_texts (cluster : Places.cluster) =
  Option.to_list (place_name cluster)
  @ Option.to_list (Places.label_detail cluster.members)

let keep ~filter query cluster =
  (* Applied to its cluster once (Features.places does), so the place's name
     is matched at most once per cluster, not once per member. *)
  let place_matches =
    lazy
      (match query with
      | Everything -> true
      | Matching {place; plants = _} -> place cluster)
  in
  fun (o : Observation.t) ->
    filter o
    &&
    match query with
    | Everything -> true
    | Matching {plants; place = _} -> (
        match o.plant_id with
        | Some p when List.exists (Plant_id.equal p) plants -> true
        | Some _ | None -> Lazy.force place_matches)
