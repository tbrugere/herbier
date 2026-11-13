module Plant = Herbier_domain.Plant
module Plant_id = Herbier_domain.Ids.Plant_id
module Taxon = Herbier_refs.Sources.Gbif.Taxon

type mode = Browse | Attach | Relink

type action =
  | Inert
  | Open of Plant.t
  | Attach_to of Plant.t
  | Create
  | Link_this

let equal_action a b =
  match (a, b) with
  | Inert, Inert | Create, Create | Link_this, Link_this -> true
  | Open p, Open q | Attach_to p, Attach_to q -> p = q
  | (Inert | Open _ | Attach_to _ | Create | Link_this), _ -> false

let matching ~plants (t : Taxon.t) =
  let keys = t.key :: Option.to_list t.accepted_key in
  List.filter
    (fun (p : Plant.t) ->
      match (p.deleted_at, p.gbif_key) with
      | None, Some k -> List.mem k keys
      | Some _, _ | None, None -> false)
    plants

let is_current ~current (p : Plant.t) =
  match current with None -> false | Some id -> Plant_id.equal id p.id

let action mode ~current ~plants t =
  let matching = matching ~plants t in
  match (List.exists (is_current ~current) matching, mode, matching) with
  | true, _, _ -> Inert
  | false, Browse, p :: _ -> Open p
  | false, Attach, p :: _ -> Attach_to p
  | false, (Browse | Attach), [] -> Create
  | false, Relink, _ -> Link_this

let other_owner ~current ~plants t =
  List.find_opt (fun p -> not (is_current ~current p)) (matching ~plants t)
