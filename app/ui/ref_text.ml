module Source = Herbier_domain.Reference.Source

let source_name = function
  | Source.Gbif -> "GBIF"
  | Source.Wikidata -> "Wikidata"
  | Source.Wikipedia -> "Wikipédia"
  | Source.Powo -> "POWO"
  | Source.Ipni -> "IPNI"
  | Source.Taxref -> "INPN"
  | Source.Tela -> "Tela Botanica"
  | Source.Eppo -> "EPPO"
  | Source.Inat -> "iNaturalist"
  | Source.Plantnet -> "Pl@ntNet"

let names_line (v : Herbier_refs.Projection.vernacular) =
  String.concat ", " v.names

let names_source_line ~family sources =
  let sources =
    match sources with
    | [] -> []
    | _ :: _ -> [String.concat ", " (List.map source_name sources)]
  in
  String.concat " · " (Option.to_list family @ sources)

let sources_line sources = String.concat ", " (List.map source_name sources)

let origin_line names =
  match (names, List.length names) with
  | [], _ -> None
  | _, n when n <= 6 -> Some (String.concat ", " names)
  | _, n ->
      Some
        (Printf.sprintf "%s et %d autres"
           (String.concat ", " (List.take 5 names))
           (n - 5))

let red_list = function
  | "LEAST_CONCERN" -> Some "LC · préoccupation mineure"
  | "NEAR_THREATENED" -> Some "NT · quasi menacée"
  | "VULNERABLE" -> Some "VU · vulnérable"
  | "ENDANGERED" -> Some "EN · en danger"
  | "CRITICALLY_ENDANGERED" -> Some "CR · en danger critique"
  | "EXTINCT_IN_THE_WILD" -> Some "EW · éteinte à l'état sauvage"
  | "EXTINCT" -> Some "EX · éteinte"
  | "DATA_DEFICIENT" -> Some "DD · données insuffisantes"
  | "NOT_EVALUATED" | "NOT_APPLICABLE" -> None
  | other -> Some other

let month_letter = function
  | 1 -> "J"
  | 2 -> "F"
  | 3 -> "M"
  | 4 -> "A"
  | 5 -> "M"
  | 6 -> "J"
  | 7 -> "J"
  | 8 -> "A"
  | 9 -> "S"
  | 10 -> "O"
  | 11 -> "N"
  | 12 -> "D"
  | _ -> ""

(* Runs of consecutive months as (first, last), ascending by first. *)
let runs months =
  List.fold_left
    (fun acc m ->
      match acc with
      | (first, last) :: rest when m = last + 1 -> (first, m) :: rest
      | _ -> (m, m) :: acc)
    [] months
  |> List.rev

(* A run ending in December and one starting in January are one run across
   the new year, which starts at its first month. *)
let wrapped = function
  | (1, last) :: (_ :: _ as rest) -> (
      match List.rev rest with
      | (first, 12) :: middle -> List.rev ((first, last) :: middle)
      | _ -> (1, last) :: rest)
  | runs -> runs

let months_text months =
  let months =
    List.sort_uniq Int.compare (List.filter (fun m -> m >= 1 && m <= 12) months)
  in
  match List.length months with
  | 12 -> "toute l'année"
  | _ ->
      String.concat ", "
        (List.map
           (fun (first, last) ->
             match first = last with
             | true -> Fr_date.month_name first
             | false ->
                 Fr_date.month_name first ^ " – " ^ Fr_date.month_name last)
           (wrapped (runs months)))

let organ_label = function
  | Herbier_domain.Reference.Organ.Flower -> "fleur"
  | Leaf -> "feuille"
  | Fruit -> "fruit"
  | Habit -> "port"

let credits (images : Herbier_domain.Reference.Image.t list) =
  let pieces =
    List.fold_left
      (fun acc (i : Herbier_domain.Reference.Image.t) ->
        let piece = Printf.sprintf "%s (%s)" i.attribution i.licence in
        match List.mem piece acc with true -> acc | false -> piece :: acc)
      [] images
    |> List.rev
  in
  match pieces with
  | [] -> ""
  | _ :: _ -> "Photos : " ^ String.concat ", " pieces

let link_label source = source_name source ^ " ↗"
