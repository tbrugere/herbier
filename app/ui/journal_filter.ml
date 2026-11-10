module Observation = Herbier_domain.Observation

let keep ~year_of ~year ~to_identify_only ~tagged (o : Observation.t) =
  (match year with None -> true | Some y -> Int.equal (year_of o) y)
  && (match to_identify_only with
    | true -> Option.is_none o.plant_id
    | false -> true)
  &&
  match (tagged, o.plant_id) with
  | [], _ -> true
  | _ :: _, None -> false
  | _ :: _, Some id -> Collection_filter.has_all_tags ~tagged id

let year_chips ~year_of ~year observations =
  let present = List.map year_of observations in
  let all = match year with None -> present | Some y -> y :: present in
  List.sort_uniq (fun a b -> Int.compare b a) all

let to_identify_chip ~to_identify_only observations =
  let n =
    List.length
      (List.filter
         (fun (o : Observation.t) -> Option.is_none o.plant_id)
         observations)
  in
  match (n, to_identify_only) with 0, false -> None | _ -> Some n
