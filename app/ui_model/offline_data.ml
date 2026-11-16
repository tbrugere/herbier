type usage = {previews : float; reference_photos : float} [@@deriving eq]
type state = Measuring | Measured of usage | Unknown [@@deriving eq]

let detail = function
  | Measuring -> "Aperçus photos … · Photos de référence …"
  | Measured {previews; reference_photos} ->
      Printf.sprintf "Aperçus photos %s · Photos de référence %s"
        (Fr_text.size previews)
        (Fr_text.size reference_photos)
  | Unknown -> "Taille inconnue"

let can_free = function
  | Measured {reference_photos; _} -> reference_photos > 0.
  | Measuring | Unknown -> false

let confirm_title = "Libérer les photos de référence ?"

let confirm_text =
  "Elles seront retéléchargées à l’ouverture de chaque fiche, avec le réseau. \
   Vos photos et vos fiches restent."

type free_failure = Busy | Failed

let free_failure_text = function
  | Busy ->
      "Des photos de référence se téléchargent : réessayez dans un instant."
  | Failed -> "La place n’a pas pu être libérée."

let freed_text n = Fr_text.size n ^ " libérés."

let freed ~before = function
  | Measured {reference_photos; _} ->
      freed_text (Float.max 0. (before -. reference_photos))
  | Measuring | Unknown -> freed_text before
