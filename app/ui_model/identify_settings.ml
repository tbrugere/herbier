module Plantnet = Herbier_identify.Plantnet
module Settings = Herbier_store.Settings

let preferences_key = "plantnet.api_key"
let bullets = "\u{2022}\u{2022}\u{2022}\u{2022}"

module Key = struct
  type t = string

  let of_input = Herbier_domain.Text.non_blank
  let to_string = Fun.id
  let equal = String.equal

  (* The byte offset of each scalar value, last first: the tail is cut at a
     scalar boundary. *)
  let starts s =
    let rec go acc i =
      match i < String.length s with
      | false -> acc
      | true ->
          go (i :: acc)
            (i + Uchar.utf_decode_length (String.get_utf_8_uchar s i))
    in
    go [] 0

  let masked k =
    (* At least 8 scalars; [from] is the 4th from the end, as [starts] lists
       the last first. *)
    match starts k with
    | _ :: _ :: _ :: from :: _ :: _ :: _ :: _ :: _ ->
        bullets ^ " " ^ String.sub k from (String.length k - from)
    | _ -> bullets
end

type key = Loading | Absent | Present of Key.t [@@deriving eq]

let key_of_stored = function
  | None -> Absent
  | Some s -> (
      match Key.of_input s with Some k -> Present k | None -> Absent)

let key_detail = function
  | Loading -> "\u{2026}"
  | Absent -> "Aucune clé"
  | Present k -> Key.masked k

type gate = Ready of Key.t | Waiting | No_key | Offline [@@deriving eq]

let gate key ~online =
  match (key, online) with
  | Loading, (true | false) -> Waiting
  | Absent, (true | false) -> No_key
  | Present k, true -> Ready k
  | Present (_ : Key.t), false -> Offline

let no_key_line =
  "Ajoutez votre clé API Pl@ntNet dans Réglages pour identifier."

let opens_on_photo ~on_photo = function
  | Ready (_ : Key.t) -> on_photo
  | Waiting | No_key | Offline -> false

type settings = {on_photo : bool; flora : Settings.flora option}

let settings_of_stored ~on_photo ~flora =
  {on_photo = Option.value ~default:true on_photo; flora}

let automatic_title = "Automatique"

let flora_id = function
  | None -> Plantnet.automatic
  | Some (f : Settings.flora) -> f.id

let flora_detail = function
  | None -> automatic_title
  | Some (f : Settings.flora) -> f.title

type flora_row = {detail : string; note : string option; enabled : bool}
[@@deriving eq]

let no_key_note = "Ajoutez votre clé API Pl@ntNet pour choisir la flore."
let flora_list_offline = "Hors-ligne : la liste des flores demande le réseau."

let flora_row ~key ~online current =
  let detail = flora_detail current in
  let disabled note = {detail; note; enabled = false} in
  match (key, online) with
  | Loading, (true | false) -> disabled None
  | Absent, (true | false) -> disabled (Some no_key_note)
  | Present (_ : Key.t), false -> disabled (Some flora_list_offline)
  | Present (_ : Key.t), true -> {detail; note = None; enabled = true}

type choice = {flora : Settings.flora option; selected : bool} [@@deriving eq]

let choices ~current projects =
  let selected_id id =
    match current with
    | None -> false
    | Some (f : Settings.flora) -> String.equal f.id id
  in
  let kept =
    List.fold_left
      (fun acc (p : Plantnet.project) ->
        match
          String.equal p.id Plantnet.automatic
          || List.exists
               (fun (q : Plantnet.project) -> String.equal q.id p.id)
               acc
        with
        | true -> acc
        | false -> p :: acc)
      [] projects
    |> List.rev
  in
  {flora = None; selected = Option.is_none current}
  :: List.map
       (fun (p : Plantnet.project) ->
         {
           flora = Some {Settings.id = p.id; title = p.title};
           selected = selected_id p.id;
         })
       kept

let filter ~query choices =
  match (String.trim query, choices) with
  | "", _ | _, [] -> choices
  | _, first :: rest ->
      first
      :: List.filter
           (fun c -> Herbier_domain.Fold.matches ~query (flora_detail c.flora))
           rest

let flora_list_generic = "La liste des flores n'a pas pu être chargée."

let flora_list_error : Plantnet.error -> string = function
  | Key_refused -> "Pl@ntNet a refusé la clé : vérifiez-la ci-dessous."
  | Quota_used_up -> "Quota Pl@ntNet du jour atteint : réessayez demain."
  | Unreachable (_ : Plantnet.unreachable) ->
      "Pl@ntNet injoignable : réessayez plus tard."
  | No_key -> no_key_note
  | Key_not_exposed
  | Refused_request (_ : int)
  | Malformed (_ : string)
  | No_plant | No_photo ->
      flora_list_generic

let section_title = "Identification"
let on_photo_label = "Identifier dès la photo"

let on_photo_detail =
  "Pl@ntNet propose les espèces avant de nommer. En ligne seulement."

let flora_title = "Flore Pl@ntNet"
let key_title = "Clé API Pl@ntNet"
let key_edit = "Modifier"
let key_placeholder = "Collez votre clé API"
let key_save = "Enregistrer"
let key_cancel = "Annuler"
let key_not_saved = "Clé non enregistrée sur le téléphone."
let key_help_before = "Clé gratuite et personnelle, à créer sur "
let key_help_link = "my.plantnet.org"
let key_help_url = "https://my.plantnet.org/"

let key_help_after =
  ". Dans votre compte Pl@ntNet, cochez « expose my API key » et ajoutez \
   https://localhost aux domaines autorisés."

let footnote =
  Printf.sprintf
    "Pl@ntNet ne conserve pas les photos envoyées. Jusqu'à %d identifications \
     par jour."
    Herbier_identify.Plantnet.daily_quota

let search_placeholder = "Flore"
let loading = "Chargement\u{2026}"
let retry = "Réessayer"
let selected_meta = "Choisie"
