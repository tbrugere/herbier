let to_input ~tz_offset_s t =
  let (y, m, d), ((h, mi, _), _) = Ptime.to_date_time ~tz_offset_s t in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d" y m d h mi

let parse s =
  let num a b =
    let f = String.sub s a b in
    match String.for_all (function '0' .. '9' -> true | _ -> false) f with
    | true -> int_of_string_opt f
    | false -> None
  in
  let sep i c = Char.equal s.[i] c in
  match String.length s with
  | (16 | 19) as n
    when sep 4 '-'
         && sep 7 '-'
         && sep 10 'T'
         && sep 13 ':'
         && (n = 16 || sep 16 ':') -> (
      let sec = match n with 19 -> num 17 2 | _ -> Some 0 in
      match (num 0 4, num 5 2, num 8 2, num 11 2, num 14 2, sec) with
      | Some y, Some m, Some d, Some h, Some mi, Some se ->
          Ptime.of_date_time ((y, m, d), ((h, mi, se), 0))
      | _ -> None)
  | _ -> None

(* [wall] is the wall clock read as UTC. The offsets a day before and a day
   after it are the two a change near it can give; an instant is the answer
   when the zone's offset there is the one subtracted to reach it. The offset
   before comes first (the earlier of a repeated hour) and also answers a
   skipped hour, as RFC 5545 §3.3.5 does. *)
let of_input ~offset s =
  let ( let* ) = Option.bind in
  let* wall = parse s in
  let day = Ptime.Span.of_int_s 86_400 in
  let* before = Option.map offset (Ptime.sub_span wall day) in
  let* after = Option.map offset (Ptime.add_span wall day) in
  let at o = Ptime.sub_span wall (Ptime.Span.of_int_s o) in
  let fits o =
    match at o with Some t when offset t = o -> Some t | Some _ | None -> None
  in
  match (fits before, fits after) with
  | Some t, _ | None, Some t -> Some t
  | None, None -> at before
