let size n =
  let ko = Float.to_int (Float.round (Float.of_int n /. 1000.)) in
  match () with
  | () when n <= 0 -> "0 o"
  | () when n < 1000 -> Printf.sprintf "%d o" n
  | () when ko < 1000 -> Printf.sprintf "%d ko" ko
  | () ->
      let tenths = Float.to_int (Float.round (Float.of_int n /. 100_000.)) in
      Printf.sprintf "%d,%d Mo" (tenths / 10) (tenths mod 10)

let title ~code ~name = code ^ " · " ^ name

let detail ~size_bytes ~communes =
  size size_bytes ^ " · " ^ Fr_text.plural communes "commune" "communes"

let unreadable = "Fichier illisible : supprimez puis retéléchargez."

let no_pack = "Aucun département téléchargé : « IGN hors-ligne » ne nomme rien."

let attribution =
  "Limites communales : IGN, Admin Express COG carto (Licence Ouverte 2.0)"
