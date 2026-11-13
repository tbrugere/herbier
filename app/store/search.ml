module Fold = Herbier_domain.Fold

let match_expression text =
  match Fold.terms text with
  | [] -> None
  | terms ->
      Some
        (String.concat " "
           (List.map
              (fun t -> "\"" ^ Fold.strip_ending (Fold.fold t) ^ "\"*")
              terms))

let matching expression =
  Plants.query
    ("select p.* from plants p where p.deleted_at is null and p.id in (select \
      plant_id from plant_search where plant_search match ?) order by "
    ^ Plants.order_by)
    [Codec.Text expression]

let plants text = Option.map matching (match_expression text)

let plants_by_name text =
  Option.map
    (fun expression -> matching ("{names tags} : (" ^ expression ^ ")"))
    (match_expression text)

let plants_or_all text = Option.value (plants text) ~default:Plants.list
