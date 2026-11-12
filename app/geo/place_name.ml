module Places = Herbier_domain.Places
module Observation = Herbier_domain.Observation

type source = Ign_online | Photon_online

let equal_source a b =
  match (a, b) with
  | Ign_online, Ign_online | Photon_online, Photon_online -> true
  | (Ign_online | Photon_online), _ -> false

let order = [Ign_online; Photon_online]

let label = function
  | Ign_online -> "IGN en ligne"
  | Photon_online -> "Photon en ligne"

let detail = function
  | Ign_online -> "Envoie la position à l’IGN (data.geopf.fr), en France."
  | Photon_online ->
      "Envoie la position à komoot (photon.komoot.io), et la recherche « \
       Chercher un lieu »."

type sources = {ign_online : bool; photon_online : bool}

let none = {ign_online = false; photon_online = false}

let enabled s = function
  | Ign_online -> s.ign_online
  | Photon_online -> s.photon_online

let equal_sources a b =
  List.for_all (fun src -> Bool.equal (enabled a src) (enabled b src)) order

let set s src b =
  match src with
  | Ign_online -> {s with ign_online = b}
  | Photon_online -> {s with photon_online = b}

let any_online s = List.exists (enabled s) order
let can_search s = s.photon_online

let allows s = function
  | Geocode.Geoplateforme -> s.ign_online
  | Geocode.Photon -> s.photon_online

let finite ({lat; lon} : Places.point) =
  Float.is_finite lat && Float.is_finite lon

let labelled_place (o : Observation.t) =
  match (Places.position_point o, o.place_label) with
  | Some point, Some l -> (
      match String.trim l with "" -> None | l -> Some (o, point, l))
  | Some _, None | None, (Some _ | None) -> None

let own observations p =
  let closer (o, d, _) (o', d', _) =
    match Float.compare d d' with
    | 0 -> Places.compare_obs o o' < 0
    | c -> c < 0
  in
  let pick best candidate =
    match best with
    | Some b when not (closer candidate b) -> best
    | Some _ | None -> Some candidate
  in
  match finite p with
  | false -> None
  | true ->
      observations
      |> List.filter_map labelled_place
      |> List.filter (fun (_, point, _) -> Places.within point p)
      |> List.map (fun (o, point, l) -> (o, Places.distance_m point p, l))
      |> List.fold_left pick None
      |> Option.map (fun (_, _, l) -> l)

type outcome = Named of string | Unknown | Deferred

let equal_outcome a b =
  match (a, b) with
  | Named a, Named b -> String.equal a b
  | Unknown, Unknown | Deferred, Deferred -> true
  | (Named _ | Unknown | Deferred), _ -> false

let outcome_to_string = function
  | Named s -> "named " ^ s
  | Unknown -> "unknown"
  | Deferred -> "deferred"

let program p = function
  | Ign_online -> Geocode.reverse_ign p
  | Photon_online -> Geocode.reverse_photon p

let ask sources p =
  let chain =
    List.fold_right
      (fun src next () ->
        match enabled sources src with
        | false -> next ()
        | true -> Geocode.or_else (program p src) next)
      order
      (fun () -> Geocode.Done (Ok None))
  in
  Geocode.map
    (Result.map (function Some s -> Named s | None -> Unknown))
    (chain ())

let resolve ~sources ~online ~labelled p =
  match finite p with
  | false -> Geocode.Done (Ok Unknown)
  | true -> (
      match (own labelled p, any_online sources, online) with
      | Some s, _, _ -> Geocode.Done (Ok (Named s))
      | None, false, _ -> Geocode.Done (Ok Unknown)
      | None, true, false -> Geocode.Done (Ok Deferred)
      | None, true, true -> ask sources p)
