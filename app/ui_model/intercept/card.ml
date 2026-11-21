module Plant = Herbier_domain.Plant
module Tag = Herbier_domain.Tag
module Observation = Herbier_domain.Observation
module Ids = Herbier_domain.Ids
module Taxon = Herbier_refs.Sources.Gbif.Taxon

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
    place_detail = None;
    note = None;
    created_at = at;
    updated_at = at;
    deleted_at = None;
  }
