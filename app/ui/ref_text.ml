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
