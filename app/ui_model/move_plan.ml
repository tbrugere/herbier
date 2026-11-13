module Observation = Herbier_domain.Observation
module Places = Herbier_domain.Places

let initial_zoom = 17.
let search_zoom = 16.
let min_zoom = 12.

(* [>=] is false for nan. *)
let can_validate ~zoom = zoom >= min_zoom
let round6 x = Float.round (x *. 1e6) /. 1e6

(* Wrapped before rounding as documented, then once more: a longitude a hair
   under 180 rounds up to 180, which belongs to -180. *)
let wrap lon =
  let w = Float.rem (lon +. 180.) 360. in
  (match w < 0. with true -> w +. 360. | false -> w) -. 180.

let normalise ({lat; lon} as p : Places.point) : Places.point option =
  match Places.finite p with
  | true ->
      let lon = round6 (wrap lon) in
      Some
        {
          lat = round6 (Float.min 90. (Float.max (-90.) lat));
          lon = (match lon >= 180. with true -> lon -. 360. | false -> lon);
        }
  | false -> None

let distance_text d =
  match Float.is_finite d with
  | false -> None
  | true -> (
      let metres = Float.round d in
      match () with
      | () when metres < 1. -> None
      | () when metres < 1000. ->
          Some (Printf.sprintf "déplacé de %.0f m" metres)
      | () when d < 9950. -> (
          let tenths = Float.to_int (Float.round (d /. 100.)) in
          match tenths mod 10 with
          | 0 -> Some (Printf.sprintf "déplacé de %d km" (tenths / 10))
          | decimal ->
              Some (Printf.sprintf "déplacé de %d,%d km" (tenths / 10) decimal))
      | () ->
          Some (Printf.sprintf "déplacé de %.0f km" (Float.round (d /. 1000.))))

let meta ~origin p =
  let shown = Option.value (normalise p) ~default:p in
  let coordinates = Places.point_text shown in
  match Option.bind origin (fun o -> distance_text (Places.distance_m o p)) with
  | Some moved -> coordinates ^ " · " ^ moved
  | None -> coordinates

let title ~origin ~origin_name ~picked p =
  match (picked, origin, origin_name) with
  | Some (name, q), _, _ when Places.within q p -> name
  | _, Some o, Some n when Places.within o p -> n
  | (Some _ | None), _, _ -> "Lieu sans nom"

let apply (o : Observation.t) p ~at =
  match normalise p with
  | None -> None
  | Some q -> (
      let before =
        Option.bind o.position (fun pos -> normalise (Places.of_position pos))
      in
      match Option.map (Places.equal_point q) before with
      | Some true -> None
      | Some false | None ->
          let same_place =
            match Places.position_point o with
            | Some from -> Places.within from q
            | None -> false
          in
          Some
            {
              o with
              position = Some {lat = q.lat; lon = q.lon; accuracy_m = None};
              place_derived = None;
              place_label =
                (match same_place with true -> o.place_label | false -> None);
              updated_at = at;
            })
