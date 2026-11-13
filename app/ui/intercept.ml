module Link = Herbier_domain.Link
module Plant = Herbier_domain.Plant
module Tag = Herbier_domain.Tag
module Observation = Herbier_domain.Observation
module Ids = Herbier_domain.Ids
module Resolve = Herbier_refs.Resolve
module Candidate = Resolve.Candidate
module Taxon = Herbier_refs.Sources.Gbif.Taxon

let cap = 4096

(* Cut at a character boundary: a UTF-8 continuation byte is 10xxxxxx. *)
let capped s =
  let rec boundary i =
    match i > 0 && Char.code s.[i] land 0xc0 = 0x80 with
    | true -> boundary (i - 1)
    | false -> i
  in
  match String.length s <= cap with
  | true -> s
  | false -> String.trim (String.sub s 0 (boundary cap))

let non_blank s = match String.trim s with "" -> None | t -> Some t
let of_url url = Option.map capped (non_blank url)

let of_share ~title ~texts =
  Option.map capped
    (match List.filter_map non_blank texts with
    | [] -> non_blank title
    | texts -> Some (String.concat "\n" texts))

let header = function
  | Link.Gbif _ -> "lien GBIF reconnu"
  | Link.Plantnet _ | Link.Plantnet_observation _ -> "lien Pl@ntNet reconnu"
  | Link.Plantuse _ -> "lien Pl@ntUse reconnu"
  | Link.Wikipedia _ -> "lien Wikipédia reconnu"
  | Link.Inpn _ -> "lien INPN reconnu"
  | Link.Tela _ -> "lien Tela Botanica reconnu"
  | Link.Powo _ -> "lien POWO reconnu"
  | Link.Inat _ -> "lien iNaturalist reconnu"
  | Link.Text _ -> "partage reçu"

let query = function
  | Link.Plantnet n | Link.Plantuse n -> n
  | Link.Wikipedia {title; _} -> title
  | Link.Text s -> String.trim s
  | Link.Gbif _ | Link.Plantnet_observation _ | Link.Inpn _ | Link.Tela _
  | Link.Powo _ | Link.Inat _ ->
      ""

type status =
  | Offline
  | Resolving
  | Failed of string
  | Found of {candidate : Candidate.t; existing : Plant.t option}
  | Search of string

let same_plant (a : Plant.t) (b : Plant.t) =
  Ids.Plant_id.equal a.id b.id && Ptime.equal a.updated_at b.updated_at

let equal_status a b =
  match (a, b) with
  | Offline, Offline | Resolving, Resolving -> true
  | Failed a, Failed b | Search a, Search b -> String.equal a b
  | Found a, Found b ->
      Candidate.equal a.candidate b.candidate
      && Option.equal same_plant a.existing b.existing
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
      or_around t (query link)

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

let name candidate ~existing =
  match existing with
  | Some (p : Plant.t) -> p.display_name
  | None -> Plant_link.display_name candidate

let meta (taxon : Taxon.t) =
  match taxon.family with Some f -> f ^ " · GBIF" | None -> "GBIF"

let place_line = function
  | Gps.Searching -> "Position… · maintenant"
  | Gps.Fix (p : Observation.position) ->
      Printf.sprintf "%.4f, %.4f · maintenant" p.lat p.lon
  | Gps.No_fix -> "Sans position · maintenant"

let recent_count = 6
let session_s = 43_200.
let live_link (l : Tag.Plant_tag.t) = Option.is_none l.deleted_at

let newest_link_at links (tag : Tag.t) =
  let ats =
    List.filter_map
      (fun (l : Tag.Plant_tag.t) ->
        match Ids.Tag_id.equal l.tag_id tag.id with
        | true -> Some l.created_at
        | false -> None)
      links
  in
  match List.sort (fun a b -> Ptime.compare b a) ats with
  | [] -> None
  | newest :: _ -> Some newest

let recent_tags ~now ~tags ~links ~except =
  let links = List.filter live_link links in
  let listed (tag : Tag.t) =
    match
      ( Option.is_none tag.deleted_at,
        List.exists (Ids.Tag_id.equal tag.id) except )
    with
    | true, false -> Option.map (fun at -> (tag, at)) (newest_link_at links tag)
    | true, true | false, _ -> None
  in
  let order ((a : Tag.t), at_a) ((b : Tag.t), at_b) =
    match Ptime.compare at_b at_a with
    | 0 -> (
        match String.compare a.name b.name with
        | 0 -> Ids.Tag_id.compare a.id b.id
        | c -> c)
    | c -> c
  in
  let recent at = Ptime.Span.to_float_s (Ptime.diff now at) <= session_s in
  List.filter_map listed tags
  |> List.stable_sort order
  |> List.take recent_count
  |> List.map (fun (tag, at) -> (tag, recent at))

let observation ~id ~at ~plant gps =
  {
    Observation.id;
    plant_id = Some plant;
    at;
    position = Gps.position gps;
    place_label = None;
    place_derived = None;
    note = None;
    created_at = at;
    updated_at = at;
    deleted_at = None;
  }
