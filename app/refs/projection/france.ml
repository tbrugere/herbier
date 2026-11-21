module Source = Herbier_domain.Reference.Source
module Inpn = Sources.Inpn

type protection = Not_protected | National | Local of string list
[@@deriving eq, show]

type red_list = {category : string; description : string option}
[@@deriving eq, show]

let cited value = Cited.v [Source.Taxref] value

let status = function
  | [] -> None
  | (s : Inpn.status) :: _ -> Some (cited s.status)

let overseas (a : Inpn.article) =
  match a.location with
  | Some {overseas = Some true; _} -> true
  | Some {overseas = Some false | None; _} | None -> false

let protection articles =
  let protecting =
    List.filter
      (fun (a : Inpn.article) ->
        String.equal a.kind "PROTECTION" && not (overseas a))
      articles
  in
  let of_scope scope =
    List.filter
      (fun (a : Inpn.article) -> String.equal a.scope scope)
      protecting
  in
  let names articles =
    List.filter_map
      (fun (a : Inpn.article) ->
        Option.map (fun (l : Inpn.location) -> l.name) a.location)
      articles
  in
  cited
    (match
       (of_scope "NATIONAL", of_scope "REGIONAL" @ of_scope "DEPARTMENTAL")
     with
    | _ :: _, _ -> National
    | [], [] -> Not_protected
    | [], local -> Local (List_ext.dedup (names local)))

let red_list = function
  | [] -> None
  | (e : Inpn.red_list_entry) :: _ ->
      Some (cited {category = e.category; description = e.description})
