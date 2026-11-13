module Photo = Herbier_domain.Photo
module Photo_id = Herbier_domain.Ids.Photo_id
module Plant_id = Herbier_domain.Ids.Plant_id
module Observation_id = Herbier_domain.Ids.Observation_id
module Observation = Herbier_domain.Observation

let ordered cover photos =
  match cover with
  | None -> photos
  | Some id -> (
      match
        List.partition (fun (ph : Photo.t) -> Photo_id.equal ph.id id) photos
      with
      | [], _ -> photos
      | cover, rest -> cover @ rest)

let choose cover photos =
  match ordered cover photos with [] -> None | c :: _ -> Some c

(* Keyed by the ids' strings: one UUID has one canonical string. *)
let by_plant observations photos =
  let plant_of = Hashtbl.create 64 in
  List.iter
    (fun (o : Observation.t) ->
      match o.plant_id with
      | Some p -> Hashtbl.replace plant_of (Observation_id.to_string o.id) p
      | None -> ())
    observations;
  let photos_of = Hashtbl.create 64 in
  List.iter
    (fun (ph : Photo.t) ->
      match
        Hashtbl.find_opt plant_of (Observation_id.to_string ph.observation_id)
      with
      | Some p ->
          let k = Plant_id.to_string p in
          let rev = Option.value ~default:[] (Hashtbl.find_opt photos_of k) in
          Hashtbl.replace photos_of k (ph :: rev)
      | None -> ())
    photos;
  Hashtbl.filter_map_inplace (fun _ rev -> Some (List.rev rev)) photos_of;
  fun id ->
    Option.value ~default:[]
      (Hashtbl.find_opt photos_of (Plant_id.to_string id))
