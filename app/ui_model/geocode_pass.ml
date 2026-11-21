module Observation = Herbier_domain.Observation
module Places = Herbier_domain.Places

type job = Name | Rename of {was : string}
type item = {o : Observation.t; p : Places.point; kind : job}

let item kind (o : Observation.t) =
  Option.map (fun pos -> {o; p = Places.of_position pos; kind}) o.position

let items ~to_geocode ~to_rename =
  List.filter_map (item Name) to_geocode
  @ List.filter_map
      (fun (o : Observation.t) ->
        Option.bind o.place_derived (fun was -> item (Rename {was}) o))
      to_rename

let yields {kind; _} ~again =
  match kind with Rename _ -> again | Name -> false

type after_save = {outcome : string; mark_tried : bool; forget : bool}

let after_save kind ~changes =
  match (kind, changes) with
  | Name, 0 -> {outcome = "unchanged"; mark_tried = true; forget = false}
  | Name, _ -> {outcome = "named"; mark_tried = false; forget = false}
  | Rename _, 0 -> {outcome = "unchanged"; mark_tried = false; forget = true}
  | Rename _, _ -> {outcome = "renamed"; mark_tried = false; forget = true}
