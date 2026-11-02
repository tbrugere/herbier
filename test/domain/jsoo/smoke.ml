(* Smoke run of herbier_domain compiled by js_of_ocaml, under node:
   - the clock and the self-seeded generator behind Ids.fresh run and
     yield version 7 UUIDs;
   - every enum round-trips;
   - Places measures and clusters as it does natively.
   Silent on success; prints the failing checks to stderr and exits 1. *)

module Ids = Herbier_domain.Ids
module Photo = Herbier_domain.Photo
module Reference = Herbier_domain.Reference
module Places = Herbier_domain.Places
module Observation = Herbier_domain.Observation

let check what ok = if ok then None else Some what

module Id_check (I : Ids.S) = struct
  let failures name =
    let a = I.to_string (I.fresh ()) and b = I.to_string (I.fresh ()) in
    let shape s =
      [
        check
          (Printf.sprintf "%s: %S has length 36" name s)
          (String.length s = 36);
        check
          (Printf.sprintf "%s: %S is version 7" name s)
          (String.length s = 36 && Char.equal s.[14] '7');
        check
          (Printf.sprintf "%s: %S has the RFC 4122 variant" name s)
          (String.length s = 36 && String.contains "89ab" s.[19]);
        check
          (Printf.sprintf "%s: %S round-trips" name s)
          (match I.of_string s with
          | Some x -> String.equal (I.to_string x) s
          | None -> false);
      ]
    in
    List.filter_map Fun.id
      (check (name ^ ": two fresh ids differ") (not (String.equal a b))
      :: (shape a @ shape b))
end

let enum_failures name all to_string of_string =
  List.filter_map
    (fun x ->
      let s = to_string x in
      check
        (Printf.sprintf "%s: %S round-trips" name s)
        (match of_string s with
        | Some y -> String.equal (to_string y) s
        | None -> false))
    all

let places_failures () =
  let one_degree_m = Places.earth_radius_m *. Float.pi /. 180. in
  let distance =
    Places.distance_m {Places.lat = 0.; lon = 0.} {Places.lat = 1.; lon = 0.}
  in
  let p = {Places.lat = 45.; lon = 5.} in
  let at_500_m = {p with lat = p.lat +. (500. /. one_degree_m)} in
  let observation n lat =
    match
      ( Ids.Observation_id.of_string
          (Printf.sprintf "00000000-0000-4000-8000-%012d" n),
        Ptime.of_float_s (1_700_000_000. +. float_of_int n) )
    with
    | Some id, Some at ->
        Some
          {
            Observation.id;
            plant_id = None;
            at;
            position = Some {Observation.lat; lon = 5.; accuracy_m = None};
            place_label = None;
            place_derived = None;
            note = None;
            created_at = at;
            updated_at = at;
            deleted_at = None;
          }
    | None, _ | _, None -> None
  in
  let clusters =
    match
      (observation 1 45., observation 2 (45. +. (300. /. one_degree_m)))
    with
    | Some a, Some b -> Some (Places.cluster [a; b])
    | None, _ | _, None -> None
  in
  List.filter_map Fun.id
    [
      check "Places: one degree of latitude is R·π/180"
        (Float.abs (distance -. one_degree_m) < 1e-6);
      check "Places: a point exactly 500 m north is within"
        (Places.within p at_500_m);
      check "Places: two observations 300 m apart are one cluster of two"
        (match clusters with
        | Some [c] -> List.length c.Places.members = 2
        | Some _ | None -> false);
    ]

let () =
  let module Plant = Id_check (Ids.Plant_id) in
  let module Observation_id = Id_check (Ids.Observation_id) in
  let module Photo_id = Id_check (Ids.Photo_id) in
  let module Tag = Id_check (Ids.Tag_id) in
  let module Plant_tag = Id_check (Ids.Plant_tag_id) in
  let module Plant_ref = Id_check (Ids.Plant_ref_id) in
  let module Reference_id = Id_check (Ids.Reference_id) in
  let failures =
    List.concat
      [
        Plant.failures "Plant_id";
        Observation_id.failures "Observation_id";
        Photo_id.failures "Photo_id";
        Tag.failures "Tag_id";
        Plant_tag.failures "Plant_tag_id";
        Plant_ref.failures "Plant_ref_id";
        Reference_id.failures "Reference_id";
        places_failures ();
        enum_failures "Photo.Original_target" Photo.Original_target.all
          Photo.Original_target.to_string Photo.Original_target.of_string;
        enum_failures "Photo.Upload_state" Photo.Upload_state.all
          Photo.Upload_state.to_string Photo.Upload_state.of_string;
        enum_failures "Reference.Source" Reference.Source.all
          Reference.Source.to_string Reference.Source.of_string;
        enum_failures "Reference.Status" Reference.Status.all
          Reference.Status.to_string Reference.Status.of_string;
        enum_failures "Reference.Organ" Reference.Organ.all
          Reference.Organ.to_string Reference.Organ.of_string;
      ]
  in
  match failures with
  | [] -> ()
  | fs ->
      List.iter prerr_endline fs;
      exit 1
