let local_date ~tz_offset_s t = fst (Ptime.to_date_time ~tz_offset_s t)

let weekday = function
  | `Mon -> "Lun."
  | `Tue -> "Mar."
  | `Wed -> "Mer."
  | `Thu -> "Jeu."
  | `Fri -> "Ven."
  | `Sat -> "Sam."
  | `Sun -> "Dim."

(* style: ocamlformat would put one month per line. *)
let months =
  [| "janvier"; "février"; "mars"; "avril"; "mai"; "juin"; "juillet"; "août";
     "septembre"; "octobre"; "novembre"; "décembre" |]
[@@ocamlformat "disable"]

let header ~with_year ((y, m, d) as date) =
  let wd =
    match Ptime.of_date date with
    | Some t -> weekday (Ptime.weekday t) ^ " "
    | None -> ""
  in
  match with_year with
  | false -> Printf.sprintf "%s%d %s" wd d months.(m - 1)
  | true -> Printf.sprintf "%s%d %s %d" wd d months.(m - 1) y

let day_header ~this_year ((y, _, _) as date) =
  header ~with_year:(not (Int.equal y this_year)) date

let long_day date = header ~with_year:true date

let time ~tz_offset_s t =
  let _, ((h, mi, _), _) = Ptime.to_date_time ~tz_offset_s t in
  Printf.sprintf "%02d:%02d" h mi

let day_time ~tz_offset_s t =
  long_day (local_date ~tz_offset_s t) ^ " · " ^ time ~tz_offset_s t

let year ~tz_offset_s t =
  let (y, _, _), _ = Ptime.to_date_time ~tz_offset_s t in
  y

let day_month (_, m, d) = Printf.sprintf "%d %s" d months.(m - 1)
let full_date ((y, _, _) as date) = Printf.sprintf "%s %d" (day_month date) y
