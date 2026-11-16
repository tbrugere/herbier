let banner ~online ~pending =
  match (online, pending) with
  | true, _ -> None
  | false, n when n <= 0 -> Some "hors-ligne"
  | false, n -> Some (Printf.sprintf "hors-ligne · %d en attente" n)

let unlinked_offline ~online =
  match online with
  | true -> ""
  | false -> " Hors-ligne : la recherche de noms reviendra avec le réseau."

let search_status ~online = function
  | Ref_search.Blank -> ""
  | Ref_search.Found (_ :: _) -> (
      match online with
      | true -> ""
      | false -> "Hors-ligne : « + » reviendra avec le réseau.")
  | Ref_search.Pending -> "Recherche…"
  | Ref_search.Found [] -> "Aucune espèce trouvée dans GBIF."
  | Ref_search.Offline -> "Recherche indisponible hors-ligne."
  | Ref_search.Failed _ -> "La recherche n'a pas abouti."
