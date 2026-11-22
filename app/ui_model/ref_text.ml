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
  | Source.Plantuse -> "Pl@ntUse"

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
let other_languages = "Autres langues"

let area_name (a : Herbier_refs.Projection.area) =
  match Option.bind a.code Wgsrpd_fr.name with
  | Some french -> french
  | None -> a.name

let origin_names areas =
  let fold = Herbier_domain.Fold.fold in
  let named =
    List.map
      (fun a ->
        let name = area_name a in
        (fold name, name))
      areas
  in
  let unique =
    List.fold_left
      (fun acc ((key, _) as x) ->
        match List.mem_assoc key acc with true -> acc | false -> x :: acc)
      [] named
  in
  List.map snd (List.sort (fun (k1, _) (k2, _) -> String.compare k1 k2) unique)

let in_source_order sources =
  List.filter (fun s -> List.mem s sources) Source.all

let origin_line names =
  match (names, List.length names) with
  | [], _ -> None
  | _, n when n <= 6 -> Some (String.concat ", " names)
  | _, n ->
      Some
        (Printf.sprintf "%s et %d autres"
           (String.concat ", " (List.take 5 names))
           (n - 5))

(* One wording for the IUCN codes, whichever list a chip comes from. *)
let red_list_label = function
  | "LC" -> Some "préoccupation mineure"
  | "NT" -> Some "quasi menacée"
  | "VU" -> Some "vulnérable"
  | "EN" -> Some "en danger"
  | "CR" -> Some "en danger critique"
  | "DD" -> Some "données insuffisantes"
  | "EW" -> Some "éteinte à l'état sauvage"
  | "EX" -> Some "éteinte"
  | "RE" -> Some "disparue en France"
  | _ -> None

let red_list_chip code =
  Option.map (fun label -> code ^ " · " ^ label) (red_list_label code)

let red_list = function
  | "LEAST_CONCERN" -> red_list_chip "LC"
  | "NEAR_THREATENED" -> red_list_chip "NT"
  | "VULNERABLE" -> red_list_chip "VU"
  | "ENDANGERED" -> red_list_chip "EN"
  | "CRITICALLY_ENDANGERED" -> red_list_chip "CR"
  | "EXTINCT_IN_THE_WILD" -> red_list_chip "EW"
  | "EXTINCT" -> red_list_chip "EX"
  | "DATA_DEFICIENT" -> red_list_chip "DD"
  | "NOT_EVALUATED" | "NOT_APPLICABLE" -> None
  | other -> Some other

let fr_status = function
  | "PRESENT" -> Some "Indigène"
  | "ENDEMIC" -> Some "Endémique"
  | "SUBENDEMIC" -> Some "Subendémique"
  | "CRYPTOGENIC" -> Some "Cryptogène"
  | "INTRODUCED" -> Some "Introduite"
  | "INVASIVE" -> Some "Introduite envahissante"
  | "NOT_NATURALIZED" -> Some "Introduite non établie"
  | "OCCASIONAL" -> Some "Occasionnelle"
  | "DOUBTFUL" -> Some "Présence douteuse"
  | "ABSENT" -> Some "Absente"
  | "DISAPPEARED" -> Some "Disparue"
  | "EXTINCT" -> Some "Éteinte"
  | _ -> None

let fr_protection = function
  | Herbier_refs.Projection.Not_protected -> "Non protégée"
  | National -> "Protégée en France"
  | Local [place] -> "Protégée (" ^ place ^ ")"
  | Local ([] | _ :: _ :: _) -> "Protégée localement"

let fr_places = function
  | Herbier_refs.Projection.Local (_ :: _ :: _ as names) ->
      Option.map (fun line -> "Protection : " ^ line) (origin_line names)
  | Not_protected | National | Local ([] | [_]) -> None

let fr_red_list ({category; description} : Herbier_refs.Projection.fr_red_list)
    =
  match (category, red_list_chip category, description) with
  | ("NA" | "NE"), _, _ -> None
  | _, Some chip, _ -> Some ("Liste rouge : " ^ chip)
  | _, None, Some d ->
      Some ("Liste rouge : " ^ category ^ " · " ^ String.lowercase_ascii d)
  | _, None, None -> Some ("Liste rouge : " ^ category)

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
let uses_label = "Utilisations"
let sources_label = "Sources"
let quoted_licence = "CC BY-SA"
let auto_extract = "extrait automatique"

let wikipedia_section ~lang ~section =
  let name =
    match lang with "fr" -> "Wikipédia" | lang -> "Wikipédia (" ^ lang ^ ")"
  in
  name ^ " · « " ^ section ^ " »"
