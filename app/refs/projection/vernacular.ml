module Text = Herbier_domain.Text
module Source = Herbier_domain.Reference.Source
module Gbif = Sources.Gbif
module Wikidata = Sources.Wikidata

module Lang = struct
  type t = Fr | En | De | It

  let all = [Fr; En; De; It]
  let to_string = function Fr -> "fr" | En -> "en" | De -> "de" | It -> "it"
end

type t = {lang : Lang.t; names : string list}

let gbif_lang = function
  | "fra" -> Some Lang.Fr
  | "eng" -> Some Lang.En
  | "deu" -> Some Lang.De
  | "ita" -> Some Lang.It
  | _ -> None

let wikidata_lang = function
  | "fr" -> Some Lang.Fr
  | "en" -> Some Lang.En
  | "de" -> Some Lang.De
  | "it" -> Some Lang.It
  | _ -> None

type vote = {vote_lang : Lang.t; name : string; from : Source.t}

let gbif_votes (page : Gbif.Vernacular.t Gbif.page) =
  List.concat_map
    (fun (v : Gbif.Vernacular.t) ->
      match Option.bind v.language gbif_lang with
      | None -> []
      | Some vote_lang ->
          List.filter_map
            (fun piece ->
              Option.map
                (fun name -> {vote_lang; name; from = Source.Gbif})
                (Text.non_blank piece))
            (String.split_on_char ',' v.name))
    page.results

let wikidata_votes (entity : Wikidata.Entity.t) =
  List.filter_map
    (fun (n : Wikidata.Entity.name) ->
      match wikidata_lang n.lang with
      | None -> None
      | Some vote_lang ->
          Option.map
            (fun name -> {vote_lang; name; from = Source.Wikidata})
            (Text.non_blank n.text))
    entity.common_names

type group = {spelling : string; count : int; froms : Source.t list}

(* Groups are built in reverse order of their first vote, then reversed, so
   a stable sort on the count breaks ties by first position. *)
let groups votes =
  List.fold_left
    (fun acc v ->
      let key = String.lowercase_ascii v.name in
      match List.mem_assoc key acc with
      | true ->
          List.map
            (fun (k, g) ->
              match k = key with
              | true ->
                  (k, {g with count = g.count + 1; froms = v.from :: g.froms})
              | false -> (k, g))
            acc
      | false -> (key, {spelling = v.name; count = 1; froms = [v.from]}) :: acc)
    [] votes
  |> List.rev_map snd
  |> List.stable_sort (fun a b -> compare b.count a.count)
  |> List.take 3

let in_source_order sources =
  List.filter (fun s -> List.mem s sources) Source.all

let vernacular votes =
  let kept =
    List.filter_map
      (fun lang ->
        match groups (List.filter (fun v -> v.vote_lang = lang) votes) with
        | [] -> None
        | gs -> Some (lang, gs))
      Lang.all
  in
  match kept with
  | [] -> None
  | _ ->
      Some
        (Cited.v
           (in_source_order
              (List.concat_map
                 (fun (_, gs) -> List.concat_map (fun g -> g.froms) gs)
                 kept))
           (List.map
              (fun (lang, gs) ->
                {lang; names = List.map (fun g -> g.spelling) gs})
              kept))
