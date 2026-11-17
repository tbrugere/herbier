module Photo = Herbier_domain.Photo
module Photo_id = Herbier_domain.Ids.Photo_id
module Drive_account = Herbier_sync_core.Auth.Drive_account

type denial =
  | Unconfigured
  | No_drive_account
  | Consent_needed
  | Consent_refused
  | Offline
  | Misconfigured
  | No_account
  | Failed
[@@deriving eq, show]

type access = Unknown | Granted | Denied of denial [@@deriving eq]

let access ~(drive : Drive_account.t) ~last =
  match (drive, last) with
  | Unconfigured, _ -> Denied Unconfigured
  | Unchosen, _ -> Denied No_drive_account
  | Chosen _, Denied (No_drive_account | Unconfigured) -> Unknown
  | ( Chosen _,
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

let not_authorized =
  "Google Drive n’est pas autorisé : autorisez-le, ou changez de compte dans « \
   Dossier Drive »."

let no_drive_account = "Choisissez le compte Google dans « Dossier Drive »."

let no_account =
  "Ce compte Google n’est plus sur le téléphone : changez-le dans « Dossier \
   Drive »."

let misconfigured = "Google refuse l’accès à Drive (configuration de l’app)."

let when_online = "Envoi dès le retour du réseau."

let blocker access ~online =
  match (access, online) with
  | Denied Unconfigured, _ ->
      Some "Envoi vers Drive indisponible dans cette version."
  | Denied No_drive_account, _ -> Some no_drive_account
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

let account_meta ~email = Option.value email ~default:"Adresse inconnue"

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
            "Google Drive n’est pas autorisé pour ce compte : les photos \
             attendent sur le téléphone. Autorisez-le, ou changez de compte \
             dans « Dossier Drive ».";
          action = Some "Autoriser";
        }
  | (Drive | App_only), _, Denied No_account ->
      Some {text = no_account; action = None}
  | (Drive | App_only), _, Denied Misconfigured ->
      Some {text = misconfigured; action = None}
  | (Drive | App_only), _, Denied No_drive_account ->
      Some
        {
          text =
            "Les photos attendent sur le téléphone : choisissez le compte et \
             le dossier dans « Dossier Drive ».";
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

type folder = Default | Picked of string [@@deriving eq, show]

let folder ~root ~(picked : Herbier_store.Settings.drive_folder option) =
  match (root, picked) with
  | Some root, Some p when String.equal root p.id -> Picked p.name
  | (Some _ | None), (Some _ | None) -> Default

let folder_name = function
  | Default -> "Herbier"
  | Picked n -> (
      match Herbier_domain.Text.non_blank n with
      | Some _ -> n
      | None -> "(sans nom)")

type picker_config = Picker_unconfigured | Picker_ready [@@deriving eq, show]

let picker_config_of_project_number number =
  match
    String.length number > 0
    && String.for_all (function '0' .. '9' -> true | _ -> false) number
  with
  | true -> Picker_ready
  | false -> Picker_unconfigured

let app_folder = "Herbier · créé par l’app"

type choose = Enabled | Disabled of string [@@deriving eq]
type folder_button = {detail : string; choose : choose} [@@deriving eq]

let no_drive_build = "Envoi vers Drive indisponible dans cette version."

let chosen_line folder email =
  let where =
    match folder with Default -> app_folder | Picked _ -> folder_name folder
  in
  where ^ " · " ^ email

let folder_button ~(drive : Drive_account.t) folder =
  match drive with
  | Unconfigured -> {detail = "Herbier"; choose = Disabled no_drive_build}
  | Unchosen -> {detail = "Aucun compte choisi"; choose = Enabled}
  | Chosen {email} -> {detail = chosen_line folder email; choose = Enabled}

type drive_option = {
  title : string;
  detail : string;
  chosen : string option;
  choose : choose;
}
[@@deriving eq]

let drive_option ~(drive : Drive_account.t) ~picker
    ~(storage : Photo.Original_target.t) folder =
  let chosen =
    match (storage, drive) with
    | Drive, Chosen {email} -> Some (chosen_line folder email)
    | Drive, (Unconfigured | Unchosen)
    | App_only, (Unconfigured | Unchosen | Chosen _) ->
        None
  in
  let choose =
    match (drive, picker) with
    | Unconfigured, (Picker_ready | Picker_unconfigured) ->
        Disabled no_drive_build
    | (Unchosen | Chosen _), Picker_unconfigured ->
        Disabled "Choix du dossier indisponible dans cette version."
    | (Unchosen | Chosen _), Picker_ready -> Enabled
  in
  {
    title = "Google Drive";
    detail = "Un sous-dossier par espèce. Aperçus gardés sur le téléphone.";
    chosen;
    choose;
  }

let drive_option_starts ~(storage : Photo.Original_target.t) ~running
    (o : drive_option) =
  match (storage, o.choose, running) with
  | App_only, Enabled, false -> true
  | App_only, Enabled, true
  | App_only, Disabled (_ : string), (true | false)
  | Drive, (Enabled | Disabled (_ : string)), (true | false) ->
      false

type pick_error =
  | Not_a_folder
  | Trashed
  | No_access
  | Offline
  | Token of denial
  | Picker_unavailable
  | Not_saved
  | Drive_failed
  | Chooser_no_account
  | Chooser_failed
  | Other_account of denial
[@@deriving eq, show]

let pick_error_text = function
  | Not_a_folder -> "Ce n’est pas un dossier."
  | Trashed -> "Ce dossier est dans la corbeille."
  | No_access -> "Herbier n’a pas accès à ce dossier."
  | Offline -> "Pas de réseau : réessayez plus tard."
  | Token No_account ->
      "Ce compte Google n’est plus sur le téléphone : utilisez un autre compte."
  | Token (Consent_needed | Consent_refused) ->
      "Google Drive n’est pas autorisé pour ce compte."
  | Token Failed ->
      "Google Drive n’a pas répondu pour ce compte : réessayez, ou utilisez un \
       autre compte."
  | Token ((Unconfigured | No_drive_account | Offline | Misconfigured) as d) ->
      Option.value (blocker (Denied d) ~online:true) ~default:not_authorized
  | Picker_unavailable -> "Google Picker n’a pas pu s’ouvrir."
  | Not_saved -> Settings_text.not_saved
  | Drive_failed -> "Drive n’a pas répondu : réessayez."
  | Chooser_no_account ->
      "Aucun compte Google sur le téléphone : ajoutez-en un dans les réglages \
       d’Android."
  | Chooser_failed -> "Le choix du compte n’a pas pu s’ouvrir. Réessayez."
  | Other_account Offline -> "Pas de réseau : rien n’a changé."
  | Other_account (Consent_needed | Consent_refused) ->
      "L’autre compte n’a pas autorisé Google Drive : rien n’a changé."
  | Other_account
      (Unconfigured | No_drive_account | Misconfigured | No_account | Failed) ->
      "L’autre compte n’a pas pu être utilisé : rien n’a changé."

let has_drive_photo (photos : Photo.t list) =
  List.exists
    (fun (p : Photo.t) ->
      match p.original_target with Drive -> true | App_only -> false)
    photos

let saved_card ~folder access ~online ~wifi_only ~queued (photos : Photo.t list)
    =
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
            ^ " → Google Drive, dossier "
            ^ folder_name folder;
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
