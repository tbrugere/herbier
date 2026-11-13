type 'a t = {date : Ptime.date; items : 'a list}

let same_date (y, m, d) (y', m', d') =
  Int.equal y y' && Int.equal m m' && Int.equal d d'

let group ~date items =
  let close acc = function
    | None -> acc
    | Some (d, xs) -> {date = d; items = List.rev xs} :: acc
  in
  let acc, current =
    List.fold_left
      (fun (acc, current) x ->
        let d = date x in
        match current with
        | Some (cd, xs) when same_date cd d -> (acc, Some (cd, x :: xs))
        | Some _ | None -> (close acc current, Some (d, [x])))
      ([], None) items
  in
  List.rev (close acc current)

module Places = Herbier_domain.Places

let place obs =
  Option.map
    (function
      | Places.Named s | Places.Derived s -> s
      | Places.Coordinates _ -> Places.unknown_name)
    (Places.label obs)

let plant_name names id =
  match
    List.find_opt (fun (p, _) -> Herbier_domain.Ids.Plant_id.equal p id) names
  with
  | Some (_, n) -> n
  | None -> "Plante supprimée"
