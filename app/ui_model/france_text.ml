let button = "Toute la France"
let loading = "Chargement\u{2026}"
let retry = "Réessayer"
let no_departements = "Aucun département reçu de l\u{2019}IGN."
let size n = Fr_text.size (Float.of_int n)
let departements n = Fr_text.plural n "département" "départements"

let scope ~total =
  "Métropole, Corse et outre-mer (Guadeloupe, Martinique, Guyane, La Réunion, \
   Mayotte) : "
  ^ departements total
  ^ "."

let estimate ~total ~todo ~bytes =
  match todo with
  | 0 -> "Tous les départements sont déjà téléchargés."
  | _ when todo = total ->
      Printf.sprintf "%s · environ %s" (departements total) (size bytes)
  | _ ->
      Printf.sprintf "%d à télécharger sur %d · environ %s" todo total
        (size bytes)

let keep_open =
  "Gardez Herbier ouvert pendant le téléchargement ; vous pourrez \
   l’interrompre et le reprendre."

let large_bytes = 10_000_000
let warn_mobile ~cellular ~bytes = cellular && bytes >= large_bytes

let mobile_warning ~bytes =
  Printf.sprintf
    "Connexion par données mobiles : environ %s seront téléchargés."
    (size bytes)

let start = "Télécharger"
let dismiss = "Annuler"
let interrupt = "Interrompre"

let progress ~position ~total ~bytes ~estimate ~current =
  Printf.sprintf "%d / %d · %s sur environ %s%s" position total (size bytes)
    (size estimate)
    (match current with None -> "" | Some name -> " · " ^ name)

type retry_reason = Connection_lost | Timed_out | Unavailable | Bad_answer

let retry_reason = function
  | Connection_lost -> "connexion perdue"
  | Timed_out -> "délai dépassé"
  | Unavailable -> "service indisponible"
  | Bad_answer -> "réponse invalide"

let retrying ~current ~reason ~attempt ~attempts ~wait_ms =
  Printf.sprintf "%s : %s, nouvel essai dans %d s (%d/%d)." current
    (retry_reason reason)
    ((wait_ms + 999) / 1000)
    attempt attempts

let cancelling = "Interruption après le département en cours…"

let complete ~downloaded ~bytes ~failed =
  let done_ =
    Printf.sprintf "Terminé : %s · %s." (departements downloaded) (size bytes)
  in
  match failed with
  | [] -> done_
  | _ :: _ ->
      Printf.sprintf
        "%s Non téléchargés : %s. Relancez « Toute la France » pour réessayer."
        done_
        (String.concat ", " failed)

let resume = "Relancez « Toute la France » pour reprendre."

let cancelled ~position ~total =
  Printf.sprintf "Interrompu à %d / %d. %s" position total resume

let stopped ~position ~total ~reason =
  Printf.sprintf "Arrêté à %d / %d : %s %s" position total reason resume

let summary ~count ~bytes = departements count ^ " · " ^ size bytes
let delete_all = "Supprimer tout"

let delete_all_question ~count ~bytes =
  match count with
  | 1 -> Printf.sprintf "Supprimer le département (%s) ?" (size bytes)
  | _ ->
      Printf.sprintf "Supprimer les %d départements (%s) ?" count (size bytes)

let delete_all_note = "Les noms déjà donnés aux observations restent."
