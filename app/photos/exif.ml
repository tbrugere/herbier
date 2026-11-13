module Observation = Herbier_domain.Observation
module Json = Herbier_net.Json

type t = {taken_at : Ptime.t option; position : Observation.position option}

let tags =
  [
    "DateTimeOriginal";
    "OffsetTimeOriginal";
    "SubSecTimeOriginal";
    "GPSLatitude";
    "GPSLatitudeRef";
    "GPSLongitude";
    "GPSLongitudeRef";
    "GPSHPositioningError";
  ]

let empty = {taken_at = None; position = None}

let string_member name json =
  match Json.member name json with Some (`String s) -> Some s | _ -> None

let number_member name json = Option.bind (Json.member name json) Json.number

let digits s =
  match Json.is_digits s with true -> int_of_string_opt s | false -> None

let date_time s =
  match
    String.length s = 19
    && s.[4] = ':'
    && s.[7] = ':'
    && s.[10] = ' '
    && s.[13] = ':'
    && s.[16] = ':'
  with
  | false -> None
  | true -> (
      let part i n = digits (String.sub s i n) in
      match (part 0 4, part 5 2, part 8 2, part 11 2, part 14 2, part 17 2) with
      | Some y, Some mo, Some d, Some h, Some mi, Some se ->
          Some ((y, mo, d), (h, mi, se))
      | _ -> None)

let offset_s s =
  let sign =
    match s with
    | "" -> None
    | _ -> ( match s.[0] with '+' -> Some 1 | '-' -> Some (-1) | _ -> None)
  in
  match (sign, String.length s = 6 && s.[3] = ':') with
  | Some sign, true -> (
      match (digits (String.sub s 1 2), digits (String.sub s 4 2)) with
      | Some h, Some m when h <= 18 && m < 60 ->
          Some (sign * ((h * 3600) + (m * 60)))
      | _ -> None)
  | _ -> None

let sub_second_ps = function
  | "" -> None
  | s ->
      let micro = String.sub (s ^ "000000") 0 6 in
      Option.map (fun us -> Int64.(mul (of_int us) 1_000_000L)) (digits micro)

let taken_at ~tz_offset_at json =
  let open Option.Syntax in
  let* date, time =
    Option.bind (string_member "DateTimeOriginal" json) date_time
  in
  let tz =
    match Option.bind (string_member "OffsetTimeOriginal" json) offset_s with
    | Some tz -> tz
    | None -> tz_offset_at date time
  in
  let+ t = Ptime.of_date_time (date, (time, tz)) in
  Option.bind
    (Option.bind (string_member "SubSecTimeOriginal" json) sub_second_ps)
    (fun ps -> Ptime.add_span t (Ptime.Span.v (0, ps)))
  |> Option.value ~default:t

let position json =
  match
    ( number_member "latitude" json,
      number_member "longitude" json,
      string_member "GPSLatitudeRef" json,
      string_member "GPSLongitudeRef" json )
  with
  | Some 0., Some 0., _, _ -> None
  (* Only exact refs: exifr negates on "S" / "W" alone, so any other value
     would leave a southern or western coordinate positive. *)
  | Some lat, Some lon, Some ("N" | "S"), Some ("E" | "W")
    when Float.abs lat <= 90. && Float.abs lon <= 180. ->
      let accuracy_m =
        match number_member "GPSHPositioningError" json with
        | Some a when a > 0. -> Some a
        | Some _ | None -> None
      in
      Some {Observation.lat; lon; accuracy_m}
  | _ -> None

let of_json ~tz_offset_at = function
  | `Assoc _ as json ->
      {taken_at = taken_at ~tz_offset_at json; position = position json}
  | _ -> empty

let of_string ~tz_offset_at text =
  match Yojson.Safe.from_string text with
  | json -> of_json ~tz_offset_at json
  | exception Yojson.Json_error _ -> empty
