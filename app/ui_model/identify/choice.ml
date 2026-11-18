module Plantnet = Herbier_identify.Plantnet
module Taxon = Herbier_refs.Sources.Gbif.Taxon
module Resolve = Herbier_refs.Resolve
module Step = Herbier_refs.Step
module Link = Herbier_domain.Link
module Plant = Herbier_domain.Plant

type resolution = Resolved of Taxon.t | Unknown | Unavailable of string
[@@deriving eq]

type t = {proposal : Plantnet.proposal; resolution : resolution option}
[@@deriving eq]

let v proposal = {proposal; resolution = None}
let resolved t r = {t with resolution = Some r}

let first_link (p : Plantnet.proposal) =
  match p.gbif with
  | Some k -> Link.Gbif k
  | None -> Link.Plantnet p.scientific_name

(* The outcome of one program, when it ends the chain. *)
let settled : Resolve.outcome -> resolution = function
  | Taxon t -> Resolved t
  | Unresolved {why = Unavailable m; _} -> Unavailable m
  | Unresolved {why = No_species | Observation_link; _} | Candidates _ ->
      Unknown

let resolve (p : Plantnet.proposal) =
  let open Step.Syntax in
  let* outcome = Resolve.resolve (first_link p) in
  match (p.gbif, outcome) with
  | Some _, Unresolved {why = No_species; _} ->
      Step.map settled (Resolve.resolve (Link.Plantnet p.scientific_name))
  | (Some _ | None), (Taxon _ | Candidates _ | Unresolved _) ->
      Step.return (settled outcome)

let plantnet_taxon (p : Plantnet.proposal) =
  Option.map
    (fun key ->
      {
        Taxon.key;
        scientific_name = p.scientific_name;
        canonical_name = Some p.name;
        authorship = (match p.author with "" -> None | a -> Some a);
        rank = None;
        status = None;
        accepted_key = None;
        family = p.family;
        vernacular_name = None;
      })
    p.gbif

let taxon t =
  match t.resolution with
  | Some (Resolved r) -> Some r
  | Some Unknown -> None
  | None | Some (Unavailable _) -> plantnet_taxon t.proposal

let keys t =
  let resolved =
    match t.resolution with
    | Some (Resolved r) -> [Some r.key; r.accepted_key]
    | None | Some (Unknown | Unavailable _) -> []
  in
  List.fold_left
    (fun acc k ->
      match k with
      | Some k when not (List.mem k acc) -> k :: acc
      | Some _ | None -> acc)
    []
    (t.proposal.gbif :: resolved)
  |> List.rev

let owner ~plants t = List.find_opt (Owned.has_key ~keys:(keys t)) plants

let new_name (p : Plantnet.proposal) =
  match p.common_names with first :: _ -> first | [] -> p.name

let label ~owner p =
  match owner with Some (o : Plant.t) -> o.display_name | None -> new_name p
