module Source = Herbier_domain.Reference.Source

type t = {source : Source.t; url : string}

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

let make source ~base ~path ~query =
  let path = String.concat "" (List.map (fun seg -> "/" ^ encode seg) path) in
  let query =
    match query with
    | [] -> ""
    | pairs ->
        "?"
        ^ String.concat "&"
            (List.map (fun (k, v) -> encode k ^ "=" ^ encode v) pairs)
  in
  {source; url = base ^ path ^ query}

let equal a b = a.source = b.source && String.equal a.url b.url
let to_string {source; url} = Source.to_string source ^ " " ^ url
