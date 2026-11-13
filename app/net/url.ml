let unreserved = function
  | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '-' | '.' | '_' | '~' -> true
  | _ -> false

let encode s =
  let buf = Buffer.create (String.length s * 3) in
  String.iter
    (fun c ->
      match unreserved c with
      | true -> Buffer.add_char buf c
      | false -> Buffer.add_string buf (Printf.sprintf "%%%02X" (Char.code c)))
    s;
  Buffer.contents buf

let rec strip_trailing_slashes s =
  match String.ends_with ~suffix:"/" s with
  | true -> strip_trailing_slashes (String.sub s 0 (String.length s - 1))
  | false -> s
