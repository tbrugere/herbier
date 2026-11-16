module Reference = Herbier_domain.Reference
module Organ = Reference.Organ
module Plant_id = Herbier_domain.Ids.Plant_id
module Image = Reference.Image
module Gbif_image = Sources.Gbif.Image

let host = "bs.plantnet.org"
let prefix = "https://" ^ host ^ "/"
let downloadable url = Herbier_net.Url.under ~prefix url

let wanted images =
  List.filter_map
    (fun organ ->
      List.find_map
        (fun (i : Gbif_image.t) ->
          match i.organ with
          | Some o when o = organ && downloadable i.url -> Some (organ, i)
          | Some _ | None -> None)
        images)
    Organ.all

type plan = {put : Image.t list; remove : Image.t list}

let ours ~plant (s : Image.t) =
  Plant_id.equal s.plant_id plant
  && Reference.Source.equal s.source Reference.Source.Plantnet

let stored_of ~plant ~stored organ =
  List.find_opt
    (fun (s : Image.t) -> ours ~plant s && Organ.equal s.organ organ)
    stored

let in_organ_order rows =
  List.concat_map
    (fun organ ->
      List.filter (fun (r : Image.t) -> Organ.equal r.organ organ) rows)
    Organ.all

let plan ~plant ~wanted ~stored =
  let put =
    List.filter_map
      (fun (organ, (i : Gbif_image.t)) ->
        let row thumb_path =
          {
            Image.plant_id = plant;
            source = Reference.Source.Plantnet;
            organ;
            remote_url = i.url;
            licence = i.licence;
            attribution = i.attribution;
            thumb_path;
          }
        in
        match stored_of ~plant ~stored organ with
        | None -> Some (row None)
        | Some s -> (
            match
              ( String.equal s.remote_url i.url,
                String.equal s.licence i.licence
                && String.equal s.attribution i.attribution )
            with
            | true, true -> None
            | true, false -> Some (row s.thumb_path)
            | false, _ -> Some (row None)))
      wanted
  in
  let remove =
    List.filter
      (fun (s : Image.t) ->
        ours ~plant s && not (List.mem_assoc s.organ wanted))
      stored
    |> in_organ_order
  in
  {put; remove}

let to_download rows =
  List.filter (fun (r : Image.t) -> Option.is_none r.thumb_path) rows
  |> in_organ_order

let shown ~wanted ~stored =
  List.filter_map
    (fun (organ, (i : Gbif_image.t)) ->
      List.find_map
        (fun (s : Image.t) ->
          match
            ( Reference.Source.equal s.source Reference.Source.Plantnet
              && Organ.equal s.organ organ
              && String.equal s.remote_url i.url,
              s.thumb_path )
          with
          | true, Some path -> Some (s, path)
          | true, None | false, _ -> None)
        stored)
    wanted

type 'failure outcome =
  | Present
  | Updated
  | Downloaded
  | Removed
  | Failed of 'failure

let changed report =
  List.exists
    (function
      | _, (Updated | Downloaded | Removed) -> true
      | _, (Present | Failed _) -> false)
    report

let report ~wanted ~plan downloads =
  let has organ rows =
    List.exists (fun (r : Image.t) -> Organ.equal r.organ organ) rows
  in
  List.filter_map
    (fun organ ->
      match
        ( has organ plan.remove,
          List.find_map
            (fun ((r : Image.t), o) ->
              match Organ.equal r.organ organ with
              | true -> Some o
              | false -> None)
            downloads,
          has organ plan.put,
          List.mem_assoc organ wanted )
      with
      | true, _, _, _ -> Some (organ, Removed)
      | false, Some o, _, _ -> Some (organ, o)
      | false, None, true, _ -> Some (organ, Updated)
      | false, None, false, true -> Some (organ, Present)
      | false, None, false, false -> None)
    Organ.all

let max_side = 300
let quality = 0.8

let fit ~width ~height =
  match (width <= 0 || height <= 0, min width height) with
  | true, _ -> (1, 1)
  | false, short when short <= max_side -> (width, height)
  | false, short ->
      let scale v =
        max 1
          (Float.to_int
             (Float.round (float v *. float max_side /. float short)))
      in
      (scale width, scale height)
