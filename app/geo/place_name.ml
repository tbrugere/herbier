module Places = Herbier_domain.Places
module Observation = Herbier_domain.Observation
module Text = Herbier_domain.Text

type source = Ign_offline | Ign_online | Photon_online [@@deriving eq]

let order = [Ign_offline; Ign_online; Photon_online]

let label = function
  | Ign_offline -> "IGN hors-ligne"
  | Ign_online -> "IGN en ligne"
  | Photon_online -> "Photon en ligne"

let detail = function
  | Ign_offline ->
      "N’envoie aucune position ; nomme d’après les communes des départements \
       téléchargés (IGN, data.geopf.fr)."
  | Ign_online -> "Envoie la position à l’IGN (data.geopf.fr), en France."
  | Photon_online ->
      "Envoie la position à komoot (photon.komoot.io), et la recherche « \
       Chercher un lieu »."

let notice_line src = label src ^ " : " ^ detail src

type sources = {ign_offline : bool; ign_online : bool; photon_online : bool}

let none = {ign_offline = false; ign_online = false; photon_online = false}

let enabled s = function
  | Ign_offline -> s.ign_offline
  | Ign_online -> s.ign_online
  | Photon_online -> s.photon_online

let equal_sources a b =
  List.for_all (fun src -> Bool.equal (enabled a src) (enabled b src)) order

let set s src b =
  match src with
  | Ign_offline -> {s with ign_offline = b}
  | Ign_online -> {s with ign_online = b}
  | Photon_online -> {s with photon_online = b}

let is_online = function
  | Ign_offline -> false
  | Ign_online | Photon_online -> true

let any_online s = List.exists (fun src -> is_online src && enabled s src) order
let any_enabled s = List.exists (enabled s) order

let offline_only s =
  List.fold_left
    (fun acc src ->
      match is_online src with
      | true -> acc
      | false -> set acc src (enabled s src))
    none order

let can_search s = s.photon_online

let allows s = function
  | Geocode.Geoplateforme -> s.ign_online
  | Geocode.Photon -> s.photon_online

let labelled_place (o : Observation.t) =
  match (Places.position_point o, o.place_label) with
  | Some point, Some l -> Option.map (fun l -> (o, point, l)) (Text.non_blank l)
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
  match Places.finite p with
  | false -> None
  | true ->
      observations
      |> List.filter_map labelled_place
      |> List.filter (fun (_, point, _) -> Places.within point p)
      |> List.map (fun (o, point, l) -> (o, Places.distance_m point p, l))
      |> List.fold_left pick None
      |> Option.map (fun (_, _, l) -> l)

type outcome = Named of Geocode.named | Unknown | Deferred [@@deriving eq]

let outcome_to_string = function
  | Named n -> "named " ^ Geocode.named_to_string n
  | Unknown -> "unknown"
  | Deferred -> "deferred"

(* The offline source is not a program: [resolve] asks it before any, and
   [ask] only folds over the online ones. *)
let program p = function
  | Ign_offline -> None
  | Ign_online -> Some (Geocode.reverse_ign p)
  | Photon_online -> Some (Geocode.reverse_photon p)

let ask sources p =
  let chain =
    List.fold_right
      (fun src next () ->
        match (enabled sources src, program p src) with
        | false, _ | true, None -> next ()
        | true, Some program -> Geocode.or_else program next)
      (List.filter is_online order)
      (fun () -> Geocode.Done (Ok None))
  in
  Geocode.map
    (Result.map (function Some n -> Named n | None -> Unknown))
    (chain ())

let offline sources communes p =
  match sources.ign_offline with
  | false -> None
  | true -> Communes.name communes p

let resolve ~sources ~online ~labelled ~communes p =
  match Places.finite p with
  | false -> Geocode.Done (Ok Unknown)
  | true -> (
      match own labelled p with
      | Some s -> Geocode.Done (Ok (Named {name = s; detail = None}))
      | None -> (
          match (offline sources communes p, any_online sources, online) with
          | Some s, _, _ -> Geocode.Done (Ok (Named {name = s; detail = None}))
          | None, false, _ -> Geocode.Done (Ok Unknown)
          | None, true, false -> Geocode.Done (Ok Deferred)
          | None, true, true -> ask sources p))
