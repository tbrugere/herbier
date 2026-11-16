module Photo = Herbier_domain.Photo
module Photo_id = Herbier_domain.Ids.Photo_id
module Lifecycle = Herbier_sync_core.Auth.Lifecycle

type denial =
  | Unconfigured
  | Signed_out
  | Consent_needed
  | Consent_refused
  | Offline
  | Misconfigured
  | No_account
  | Failed
[@@deriving eq]

type access = Unknown | Granted | Denied of denial [@@deriving eq]

let access ~(account : Lifecycle.status) ~last =
  match (account, last) with
  | Unconfigured, _ -> Denied Unconfigured
  | Signed_out, _ -> Denied Signed_out
  | Restoring, _ -> Unknown
  | Signed_in _, Denied (Signed_out | Unconfigured) -> Unknown
  | ( Signed_in _,
      ( Unknown | Granted
      | Denied
          ( Consent_needed | Consent_refused | Offline | Misconfigured
          | No_account | Failed ) ) ) ->
      last

type entry = {
  photo_id : Photo_id.t;
  state : Photo.Upload_state.t option;
  running : bool;
}

type queue = {
  waiting : int;
  failed : int;
  sending : int;
  last_upload : Ptime.t option;
  queued : Photo_id.t list;
}
[@@deriving eq]

let empty_queue =
  {waiting = 0; failed = 0; sending = 0; last_upload = None; queued = []}

let queue_of ~last_upload entries =
  List.fold_left
    (fun q (e : entry) ->
      match e.state with
      | Some Pending ->
          {
            q with
            waiting = q.waiting + 1;
            sending = (q.sending + match e.running with true -> 1 | false -> 0);
          }
      | Some Failed -> {q with failed = q.failed + 1}
      | Some (Uploaded | Original_missing) | None -> q)
    {
      empty_queue with
      last_upload;
      queued = List.map (fun (e : entry) -> e.photo_id) entries;
    }
    entries

let pending_count q = q.waiting + q.failed
let send_enabled q = pending_count q > 0

let queue_title q =
  let base =
    match pending_count q with
    | 0 -> "Aucune photo en attente"
    | n -> Fr_text.plural n "photo en attente" "photos en attente"
  in
  match q.failed with
  | 0 -> base
  | f -> Printf.sprintf "%s · %d en échec" base f

let not_authorized = "Google Drive n’est pas autorisé."
let no_account = "Aucun compte Google sur le téléphone."

let misconfigured = "Google refuse l’accès à Drive (configuration de l’app)."

let when_online = "Envoi dès le retour du réseau."

let blocker access ~online =
  match (access, online) with
  | Denied Unconfigured, _ ->
      Some "Envoi vers Drive indisponible dans cette version."
  | Denied Signed_out, _ -> Some "Connectez-vous pour envoyer les photos."
  | Denied (Consent_needed | Consent_refused), _ -> Some not_authorized
  | Denied No_account, _ -> Some no_account
  | Denied Misconfigured, _ -> Some misconfigured
  | Denied (Offline | Failed), _ | (Unknown | Granted), false ->
      Some when_online
  | (Unknown | Granted), true -> None

let queue_status access ~online ~wifi_only q =
  match pending_count q with
  | 0 -> None
  | _ -> (
      match blocker access ~online with
      | Some _ as b -> b
      | None ->
          Some
            (match () with
            | () when q.failed > 0 ->
                "Échec de l’envoi : « Envoyer maintenant » pour réessayer."
            | () when q.sending > 0 -> "Envoi en cours…"
            | () when wifi_only -> "Envoi en Wi-Fi seulement."
            | () -> "Envoi en attente."))

let previous_day date =
  Option.bind (Ptime.of_date date) (fun t ->
      Option.map Ptime.to_date (Ptime.sub_span t (Ptime.Span.of_int_s 86_400)))

let same_date (y, m, d) (y', m', d') =
  Int.equal y y' && Int.equal m m' && Int.equal d d'

let last_sent ~now ~tz_offset_s = function
  | None -> "Aucun envoi pour l’instant."
  | Some at ->
      let today = Fr_date.local_date ~tz_offset_s now in
      let day = Fr_date.local_date ~tz_offset_s at in
      let label =
        match () with
        | () when Ptime.is_later at ~than:now || same_date day today ->
            "aujourd’hui"
        | ()
          when Option.fold ~none:false ~some:(same_date day)
                 (previous_day today) ->
            "hier"
        | () ->
            Fr_date.day_header ~this_year:(Fr_date.year ~tz_offset_s now) day
      in
      Printf.sprintf "Dernier envoi : %s, %s" label
        (Fr_date.time ~tz_offset_s at)

let account_meta ~email ~(storage : Photo.Original_target.t) access =
  let address = Option.value email ~default:"Adresse inconnue" in
  match (storage, access) with
  | Drive, Granted -> address ^ " · Drive"
  | Drive, (Unknown | Denied _) | App_only, (Unknown | Granted | Denied _) ->
      address

type prompt = {text : string; action : string option} [@@deriving eq]

(* After « Les envoyer quand même » the storage is App_only but photos still
   wait for Drive: the prompt stays while they do. *)
let drive_prompt ~(storage : Photo.Original_target.t) ~pending access =
  match (storage, pending, access) with
  | App_only, 0, (Unknown | Granted | Denied _) -> None
  | (Drive | App_only), _, Denied (Consent_needed | Consent_refused) ->
      Some
        {
          text =
            "Google Drive n’est pas autorisé : les photos attendent sur le \
             téléphone.";
          action = Some "Autoriser";
        }
  | (Drive | App_only), _, Denied No_account ->
      Some {text = no_account; action = None}
  | (Drive | App_only), _, Denied Misconfigured ->
      Some {text = misconfigured; action = None}
  | (Drive | App_only), _, Denied Signed_out ->
      Some
        {
          text = "Connectez-vous pour envoyer les photos vers Drive.";
          action = None;
        }
  | ( (Drive | App_only),
      _,
      (Unknown | Granted | Denied (Unconfigured | Offline | Failed)) ) ->
      None

type dialog = {title : string; text : string} [@@deriving eq]

let stop_dialog n =
  {
    title =
      (match n with
      | 1 -> "1 photo attend l’envoi vers Drive"
      | n -> Printf.sprintf "%d photos attendent l’envoi vers Drive" n);
    text =
      "Sans envoi, leur original est effacé du téléphone ; la copie compressée \
       reste.";
  }

type card = {title : string; detail : string} [@@deriving eq]

let kept = "Copies compressées gardées sur le téléphone."

let has_drive_photo (photos : Photo.t list) =
  List.exists
    (fun (p : Photo.t) ->
      match p.original_target with Drive -> true | App_only -> false)
    photos

let saved_card access ~online ~wifi_only ~queued (photos : Photo.t list) =
  let drive =
    List.filter
      (fun (p : Photo.t) ->
        match p.original_target with Drive -> true | App_only -> false)
      photos
  in
  let has state =
    List.exists
      (fun (p : Photo.t) -> Photo.Upload_state.equal state p.upload_state)
      drive
  in
  (* A Failed photo without a queue row lost its original when it was saved:
     nothing can send it again. *)
  let failed ~in_queue =
    List.exists
      (fun (p : Photo.t) ->
        Photo.Upload_state.equal Failed p.upload_state
        && Bool.equal in_queue (List.exists (Photo_id.equal p.id) queued))
      drive
  in
  match List.length drive with
  | 0 -> None
  | n ->
      let uploaded =
        List.length
          (List.filter
             (fun (p : Photo.t) ->
               Photo.Upload_state.equal Uploaded p.upload_state)
             drive)
      in
      let detail =
        match () with
        | () when uploaded = n ->
            (match n with 1 -> "Envoyée" | _ -> "Envoyées")
            ^ " dans Google Drive. "
            ^ kept
        | () when has Original_missing ->
            "Original introuvable dans Google Drive : la copie compressée \
             reste."
        | () when failed ~in_queue:true ->
            "Échec de l’envoi : « Envoyer maintenant » dans Réglages."
        | () when failed ~in_queue:false ->
            "Original non conservé : la copie compressée reste."
        | () -> (
            match blocker access ~online with
            | Some b -> b
            | None -> (
                match () with
                | () when wifi_only -> "Envoi en Wi-Fi seulement. " ^ kept
                | () when uploaded > 0 ->
                    Printf.sprintf "%d sur %d envoyées." uploaded n
                | () -> "Envoi en cours. " ^ kept))
      in
      Some
        {
          title =
            Fr_text.plural n "photo" "photos"
            ^ " → Google Drive, dossier Herbier";
          detail;
        }

let viewer_badge (p : Photo.t) =
  match (p.original_target, p.upload_state) with
  | Drive, Uploaded -> "Google Drive"
  | Drive, (Pending | Failed) -> "↑ en attente"
  | Drive, Original_missing
  | App_only, (Pending | Uploaded | Failed | Original_missing) ->
      "local"

type viewer_drive = Open of string | Missing | Hidden [@@deriving eq]

let viewer_drive (p : Photo.t) =
  match (p.original_target, p.upload_state) with
  | Drive, Uploaded -> (
      match Option.bind p.drive_file_id Herbier_domain.Text.non_blank with
      | Some id -> Open id
      | None -> Hidden)
  | Drive, Original_missing -> Missing
  | Drive, (Pending | Failed)
  | App_only, (Pending | Uploaded | Failed | Original_missing) ->
      Hidden
