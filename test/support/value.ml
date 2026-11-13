let time s =
  match Ptime.of_rfc3339 s with
  | Ok (t, _, _) -> t
  | Error _ -> invalid_arg ("fixture time " ^ s)

let uuid4 n = Printf.sprintf "00000000-0000-4000-8000-%012x" n
let uuid7 n = Printf.sprintf "01965d4e-0000-7000-8000-%012x" n

let id what of_string s =
  match of_string s with Some x -> x | None -> invalid_arg ("fixture " ^ what)
