module Link = Herbier_domain.Link
module Plant = Herbier_domain.Plant
module Resolve = Herbier_refs.Resolve
module Candidate = Resolve.Candidate
module Taxon = Herbier_refs.Sources.Gbif.Taxon

type status =
  | Offline
  | Resolving
  | Failed of string
  | Found of {candidate : Candidate.t; existing : Plant.t option}
  | Search of string

let equal_status a b =
  match (a, b) with
  | Offline, Offline | Resolving, Resolving -> true
  | Failed a, Failed b | Search a, Search b -> String.equal a b
  | Found a, Found b ->
      Candidate.equal a.candidate b.candidate
      && Option.equal Plant_version.equal a.existing b.existing
  | (Offline | Resolving | Failed _ | Found _ | Search _), _ -> false

type t = {
  link : Link.t;
  around : string;  (** the text without its URLs *)
  status : status;
  seq : int;
  plants : Plant.t list;
}

let link t = t.link
let status t = t.status
let seq t = t.seq

type effect_ =
  | No_effect
  | Resolve of {seq : int}
  | Name of {seq : int; taxon : Taxon.t}

(* What 4i is prefilled with when the link itself names nothing: the words
   shared around it. *)
let or_around t = function "" -> t.around | q -> q

let prefill t =
  match t.link with
  | Link.Text _ -> t.around
  | Link.(
      ( Gbif _ | Plantnet _ | Plantnet_observation _ | Plantuse _ | Wikipedia _
      | Inpn _ | Tela _ | Powo _ | Inat _ ) as link) ->
      or_around t (Labels.query link)

let init ~online ~plants text =
  let link = Link.classify text in
  let t =
    {link; around = Link.without_urls text; status = Resolving; seq = 0; plants}
  in
  match link with
  | Link.Text _ | Link.Plantnet_observation _ ->
      ({t with status = Search (prefill t)}, No_effect)
  | Link.Gbif _ | Link.Plantnet _ | Link.Plantuse _ | Link.Wikipedia _
  | Link.Inpn _ | Link.Tela _ | Link.Powo _ | Link.Inat _ -> (
      match online with
      | true -> (t, Resolve {seq = 0})
      | false -> ({t with status = Offline}, No_effect))

let awaited ~seq t =
  match t.status with
  | Resolving -> seq = t.seq
  | Offline | Failed _ | Found _ | Search _ -> false

let resolved ~seq outcome t =
  match awaited ~seq t with
  | false -> (t, No_effect)
  | true -> (
      match outcome with
      | Resolve.Taxon taxon -> (t, Name {seq; taxon})
      | Resolve.Candidates _ -> ({t with status = Search (prefill t)}, No_effect)
      | Resolve.Unresolved {query = q; why = No_species | Observation_link} ->
          ({t with status = Search (or_around t q)}, No_effect)
      | Resolve.Unresolved {why = Unavailable m; _} ->
          ({t with status = Failed m}, No_effect))

let named ~seq (candidate : Candidate.t) t =
  match awaited ~seq t with
  | false -> t
  | true ->
      let existing =
        match
          Ref_pick.action Ref_pick.Browse ~current:None ~plants:t.plants
            candidate.taxon
        with
        | Ref_pick.Open p -> Some p
        | Ref_pick.Inert | Ref_pick.Attach_to _ | Ref_pick.Create
        | Ref_pick.Link_this ->
            None
      in
      {t with status = Found {candidate; existing}}

let restart t = {t with status = Resolving; seq = t.seq + 1}

let network ~online t =
  match (online, t.status) with
  | false, (Resolving | Failed _) ->
      ({t with status = Offline; seq = t.seq + 1}, No_effect)
  | true, Offline ->
      let t = restart t in
      (t, Resolve {seq = t.seq})
  | false, (Offline | Found _ | Search _)
  | true, (Resolving | Failed _ | Found _ | Search _) ->
      (t, No_effect)

let retry ~online t =
  match (t.status, online) with
  | Failed _, true ->
      let t = restart t in
      (t, Resolve {seq = t.seq})
  | Failed _, false -> ({t with status = Offline}, No_effect)
  | (Offline | Resolving | Found _ | Search _), _ -> (t, No_effect)

let search_query t =
  match t.status with
  | Found {candidate; _} -> Taxon.latin candidate.taxon
  | Search q -> q
  | Offline | Resolving | Failed _ -> prefill t
