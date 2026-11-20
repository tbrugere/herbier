module Plant = Herbier_domain.Plant
module Observation = Herbier_domain.Observation
module Places = Herbier_domain.Places
module Plant_id = Herbier_domain.Ids.Plant_id
module Choice = Identify.Choice

type target = Existing of Plant.t | Free of string | To_identify

type choice =
  | Target of target
  | Linked of {name : string; taxon : Herbier_refs.Sources.Gbif.Taxon.t}

let fold s = String.lowercase_ascii (String.trim s)

let target ~plants ~chosen text =
  let t = fold text in
  match (chosen, String.trim text) with
  | Some (p : Plant.t), _ when String.equal (fold p.display_name) t ->
      Existing p
  | _, "" -> To_identify
  | _, name -> (
      let named (p : Plant.t) =
        List.exists
          (fun n -> String.equal (fold n) t)
          (p.display_name :: p.aliases)
      in
      match List.find_opt named plants with
      | Some p -> Existing p
      | None -> Free name)

let of_choice ~plants (c : Choice.t) =
  match (Choice.owner ~plants c, Choice.taxon c) with
  | Some p, (Some _ | None) -> Target (Existing p)
  | None, Some taxon -> Linked {name = Choice.new_name c.proposal; taxon}
  | None, None ->
      Target (target ~plants ~chosen:None (Choice.new_name c.proposal))

let seen_here ~here observations plants =
  let here = Places.of_position here in
  let near =
    List.filter_map
      (fun (o : Observation.t) ->
        match (o.plant_id, o.position) with
        | Some id, Some pos ->
            let p = Places.of_position pos in
            if Places.within here p then Some (id, Places.distance_m here p)
            else None
        | _ -> None)
      observations
  in
  let sorted = List.stable_sort (fun (_, a) (_, b) -> Float.compare a b) near in
  let ids =
    List.rev
      (List.fold_left
         (fun acc (id, _) ->
           if List.exists (Plant_id.equal id) acc then acc else id :: acc)
         [] sorted)
  in
  List.filter_map
    (fun id ->
      List.find_opt (fun (p : Plant.t) -> Plant_id.equal p.id id) plants)
    ids

let fix_window_s = 600.

let when_where ~now ~fix = function
  | [] -> (now, fix)
  | (taken_at, position) :: _ -> (
      let at = Option.value taken_at ~default:now in
      match position with
      | Some p -> (at, Some p)
      | None -> (
          match
            Float.abs (Ptime.Span.to_float_s (Ptime.diff now at))
            <= fix_window_s
          with
          | true -> (at, fix)
          | false -> (at, None)))

let save_label = "Enregistrer"
let shutter_label = "Prendre la photo"
let flip_label = "Changer de caméra"
let pending_label = "Photo en cours"
let cancel_pending_label = "Annuler la photo en cours"
