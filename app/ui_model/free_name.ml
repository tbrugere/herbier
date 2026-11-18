module Observation = Herbier_domain.Observation
module Photo = Herbier_domain.Photo
module Observation_id = Herbier_domain.Ids.Observation_id
module Choice = Identify.Choice

let identify_label = "Identifier"
let search_label = "Chercher un nom"

type sent = {observation : Observation.t; photos : Photo.t list} [@@deriving eq]

let newer (a : Observation.t) (b : Observation.t) =
  match Ptime.compare a.at b.at with
  | 0 -> Observation_id.compare a.id b.id > 0
  | c -> c > 0

let sent ~observations ~photos =
  let photos_of (o : Observation.t) =
    List.filter
      (fun (p : Photo.t) ->
        match p.deleted_at with
        | Some (_ : Ptime.t) -> false
        | None -> Observation_id.equal p.observation_id o.id)
      photos
  in
  let candidate best (o : Observation.t) =
    match (o.deleted_at, photos_of o, best) with
    | Some (_ : Ptime.t), _, _ | None, [], _ -> best
    | None, (_ :: _ as own), None -> Some (o, own)
    | None, (_ :: _ as own), Some (b, _) when newer o b -> Some (o, own)
    | None, _ :: _, Some _ -> best
  in
  Option.map
    (fun (observation, own) ->
      {
        observation;
        photos =
          List.take Herbier_identify.Organ.max_photos
            (List.stable_sort Photo.compare_strip own);
      })
    (List.fold_left candidate None observations)

let identify_enabled = To_identify.identify_enabled

let no_photo_line =
  "Aucune observation de cette plante n'a de photo à envoyer à Pl@ntNet."

let identify_line (gate : Identify_settings.gate) ~photos =
  match (photos, gate) with
  | 0, (Ready _ | Waiting | Offline | No_key) -> Some no_photo_line
  | _, No_key -> Some Identify_settings.no_key_line
  | _, (Offline | Ready _ | Waiting) -> None

let identify_aria = To_identify.identify_aria

type link =
  | Link of {name : string; taxon : Herbier_refs.Sources.Gbif.Taxon.t}
  | Unknown_to_gbif
  | Gbif_unavailable
[@@deriving eq, show {with_path = false}]

let link (c : Choice.t) =
  match (Choice.taxon c, c.resolution) with
  | Some taxon, (_ : Choice.resolution option) ->
      Link {name = Choice.new_name c.proposal; taxon}
  | None, Some Unknown -> Unknown_to_gbif
  | None, (None | Some (Resolved _ | Unavailable _)) -> Gbif_unavailable

let problem = function
  | Link _ -> None
  | Unknown_to_gbif ->
      Some "GBIF ne connaît pas cette espèce : la fiche garde son nom libre."
  | Gbif_unavailable ->
      Some
        "GBIF n'a pas répondu : la fiche n'a pas été liée. Réessayez avec le \
         réseau."

let link_failed = "La fiche n'a pas pu être liée."
let plant_gone = "Cette plante n'est plus dans l'herbier."
