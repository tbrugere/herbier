let title ~code ~name = code ^ " · " ^ name

let detail ~size_bytes ~communes =
  Fr_text.size (Float.of_int size_bytes)
  ^ " · "
  ^ Fr_text.plural communes "commune" "communes"

let unreadable = "Fichier illisible : supprimez puis retéléchargez."

let no_pack = "Aucun département téléchargé : « IGN hors-ligne » ne nomme rien."

let attribution =
  "Limites communales : IGN, Admin Express COG carto (Licence Ouverte 2.0)"
