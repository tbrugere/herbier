module Source = Herbier_domain.Reference.Source
module Url = Herbier_net.Url

type t = {source : Source.t; url : string} [@@deriving eq]

let make source ~base ~path ~query =
  let path =
    String.concat "" (List.map (fun seg -> "/" ^ Url.encode seg) path)
  in
  let query =
    match query with
    | [] -> ""
    | pairs ->
        "?"
        ^ String.concat "&"
            (List.map (fun (k, v) -> Url.encode k ^ "=" ^ Url.encode v) pairs)
  in
  {source; url = base ^ path ^ query}

let to_string {source; url} = Source.to_string source ^ " " ^ url
