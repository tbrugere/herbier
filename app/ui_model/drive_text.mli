(** The Drive-related texts of 4e, 4m and 5e (architecture §5), from the photo
    rows, the upload queue's state and the Drive access. Pure: the screens and
    App compute the inputs. *)

module Photo := Herbier_domain.Photo
module Photo_id := Herbier_domain.Ids.Photo_id

(** Why no Drive token can be had (App maps [Herbier_sync.Auth.drive_error]). *)
type denial =
  | Unconfigured  (** a build without a Google web client id *)
  | No_drive_account  (** no Drive account chosen in 4m « Dossier Drive » *)
  | Consent_needed
  | Consent_refused
  | Offline
  | Misconfigured
  | No_account
      (** no usable Google account on the device, or the chosen one removed *)
  | Failed  (** any other failure (Play Services, no plugin) *)

val equal_denial : denial -> denial -> bool
val pp_denial : Format.formatter -> denial -> unit
val show_denial : denial -> string

type access = Unknown | Granted | Denied of denial

val equal_access : access -> access -> bool

val access :
  drive:Herbier_sync_core.Auth.Drive_account.t -> last:access -> access
(** What the screens show from the Drive account (the Supabase session plays no
    part): [Unconfigured] → [Denied Unconfigured]; [Unchosen] →
    [Denied No_drive_account]; [Chosen _] → [last] (the last token outcome for
    the chosen account; a stale [Denied No_drive_account] /
    [Denied Unconfigured] there reads as [Unknown]). *)

type entry = {
  photo_id : Photo_id.t;
  state : Photo.Upload_state.t option;  (** [None]: photo absent or deleted *)
  running : bool;  (** its job is [Running] *)
}
(** One row of the queue as App reads it ([Upload_queue.entries]). *)

type queue = {
  waiting : int;  (** rows whose photo is [Pending] *)
  failed : int;  (** rows whose photo is [Failed] *)
  sending : int;  (** [Pending] rows whose job is [Running] *)
  last_upload : Ptime.t option;
  queued : Photo_id.t list;  (** every row's photo, counted or not *)
}

val equal_queue : queue -> queue -> bool

val empty_queue : queue
(** No row, no upload yet. *)

val queue_of : last_upload:Ptime.t option -> entry list -> queue
(** Rows whose photo is absent, [Uploaded] or [Original_missing] (the next pass
    discards them) are not counted. *)

val pending_count : queue -> int
(** [waiting + failed]: the photos waiting on this phone (4d, 4m). *)

val queue_title : queue -> string
(** « Aucune photo en attente » (0); « 1 photo en attente »; « 3 photos en
    attente »; with [failed > 0], « · <failed> en échec » appended (« 3 photos
    en attente · 1 en échec »). *)

val blocker : access -> online:bool -> string option
(** Why waiting photos cannot leave, first that applies: [Denied Unconfigured] →
    « Envoi vers Drive indisponible dans cette version. »;
    [Denied No_drive_account] → « Choisissez le compte Google dans « Dossier
    Drive ». »; [Denied (Consent_needed | Consent_refused)] → « Google Drive
    n’est pas autorisé : autorisez-le, ou changez de compte dans « Dossier Drive
    ». »; [Denied No_account] → « Ce compte Google n’est plus sur le téléphone :
    changez-le dans « Dossier Drive ». »; [Denied Misconfigured] → « Google
    refuse l’accès à Drive (configuration de l’app). »; [not online] or
    [Denied (Offline | Failed)] → « Envoi dès le retour du réseau. »; else
    [None]. *)

val queue_status :
  access -> online:bool -> wifi_only:bool -> queue -> string option
(** 4m's line under the title; [None] when nothing waits. Else {!blocker}; else
    [failed > 0] → « Échec de l’envoi : « Envoyer maintenant » pour réessayer.
    »; [sending > 0] → « Envoi en cours… »; [wifi_only] → « Envoi en Wi-Fi
    seulement. »; else « Envoi en attente. ». *)

val last_sent : now:Ptime.t -> tz_offset_s:int -> Ptime.t option -> string
(** « Dernier envoi : aujourd’hui, 14:07 », « … hier, 19:42 » (the local date
    before [now]'s), « … Ven. 12 juin, 19:42 » ({!Fr_date.day_header} with
    [now]'s year), « Aucun envoi pour l’instant. » for [None]. An instant after
    [now] reads as today. *)

val send_enabled : queue -> bool
(** [pending_count q > 0]. *)

val account_meta : email:string option -> string
(** 4m sync account card (signed in): the address, or « Adresse inconnue »
    without. The Drive account may differ: it is « Dossier Drive »'s. *)

(** {1 The Drive folder (4m « Dossier Drive »)} *)

(** Where originals go: the app's « Herbier », or a folder the user picked. *)
type folder = Default | Picked of string  (** its name *)

val equal_folder : folder -> folder -> bool
val pp_folder : Format.formatter -> folder -> unit
val show_folder : folder -> string

val folder :
  root:string option ->
  picked:Herbier_store.Settings.drive_folder option ->
  folder
(** [Picked p.name] iff [picked = Some p] and [root = Some p.id]; else [Default]
    (no pick, or an upload replaced the picked root). *)

val folder_name : folder -> string
(** [Default] → « Herbier »; [Picked n] → [n], or « (sans nom) » when blank. *)

(** Whether this build can open Google Picker (its Cloud project number set). *)
type picker_config = Picker_unconfigured | Picker_ready

val equal_picker_config : picker_config -> picker_config -> bool
val pp_picker_config : Format.formatter -> picker_config -> unit
val show_picker_config : picker_config -> string

val picker_config_of_project_number : string -> picker_config
(** [Picker_ready] iff the Cloud project number is non-empty and all ASCII
    digits (not trimmed: the release script refuses anything else). *)

val app_folder : string
(** « Herbier · créé par l’app »: the app's folder, as 4m names it. *)

(** Whether the « Dossier Drive » button opens the sheet. *)
type choose = Enabled | Disabled of string  (** the muted line saying why *)

val equal_choose : choose -> choose -> bool

type folder_button = {
  detail : string;  (** under the title « Dossier Drive » *)
  choose : choose;
}
(** 4m « Dossier Drive »: the one button that opens the sheet choosing the Drive
    account and folder. *)

val equal_folder_button : folder_button -> folder_button -> bool

val folder_button :
  drive:Herbier_sync_core.Auth.Drive_account.t -> folder -> folder_button
(** - [Unconfigured] → detail « Herbier », [Disabled] « Envoi vers Drive
      indisponible dans cette version. »
    - [Unchosen] → detail « Aucun compte choisi », [Enabled].
    - [Chosen {email}] → detail « <where> · <email> », where [where] is
      {!app_folder} for [Default] and {!folder_name} for [Picked]; [Enabled].
      The Picker's availability does not disable the button: without it, the
      sheet still chooses the account, and for a legacy install (storage Drive,
      no account) it makes the first choice, whose only folder is then the app's
      « Herbier » (« Par défaut »). *)

type drive_option = {
  title : string;  (** « Google Drive » *)
  detail : string;
      (** « Un sous-dossier par espèce. Aperçus gardés sur le téléphone. » *)
  chosen : string option;  (** the chosen folder and account, under [detail] *)
  choose : choose;  (** [Disabled reason]: the radio is not selectable *)
}
(** 4m « Où vont mes photos »'s Drive radio. *)

val equal_drive_option : drive_option -> drive_option -> bool

val drive_option :
  drive:Herbier_sync_core.Auth.Drive_account.t ->
  picker:picker_config ->
  storage:Photo.Original_target.t ->
  folder ->
  drive_option
(** [title] and [detail] fixed (no folder name in the title). [chosen]:
    [storage = Drive] and [drive = Chosen {email}] → [Some "<where> · <email>"],
    [where] as in {!folder_button}; else [None] (under [App_only] an older
    choice is not where photos go, and choosing Drive picks again; [Drive] with
    no account is the legacy state, which the « Dossier Drive » row prompts).
    [choose], first that applies: [drive = Unconfigured] →
    [Disabled "Envoi vers Drive indisponible dans cette version."];
    [picker = Picker_unconfigured] →
    [Disabled "Choix du dossier indisponible dans cette version."]; else
    [Enabled]. The reason is given whatever [storage] (a legacy Drive install in
    such a build sees the radio checked but disabled). *)

val drive_option_starts :
  storage:Photo.Original_target.t -> running:bool -> drive_option -> bool
(** Whether a tap on the Drive radio starts a choice: [storage = App_only],
    [choose = Enabled] and no choice [running]. Already Drive, disabled, or a
    choice running: the tap is ignored. *)

(** Why the « Dossier Drive » sheet did not change the account or folder. *)
type pick_error =
  | Not_a_folder
  | Trashed
  | No_access
  | Offline
  | Token of denial
  | Picker_unavailable  (** Google Picker did not load or could not open *)
  | Not_saved  (** the settings write failed *)
  | Drive_failed  (** any other Drive error *)
  | Chooser_no_account  (** the account chooser had no account to offer *)
  | Chooser_failed  (** the account chooser could not open *)
  | Other_account of denial
      (** no token for an account chosen in the sheet: the sheet went back to
          the stored account *)

val equal_pick_error : pick_error -> pick_error -> bool
val pp_pick_error : Format.formatter -> pick_error -> unit
val show_pick_error : pick_error -> string

val pick_error_text : pick_error -> string
(** « Ce n’est pas un dossier. »; « Ce dossier est dans la corbeille. »; «
    Herbier n’a pas accès à ce dossier. »; « Pas de réseau : réessayez plus
    tard. »; [Token No_account] → « Ce compte Google n’est plus sur le téléphone
    : utilisez un autre compte. »; [Token (Consent_needed | Consent_refused)] →
    « Google Drive n’est pas autorisé pour ce compte. »; [Token Failed] → «
    Google Drive n’a pas répondu pour ce compte : réessayez, ou utilisez un
    autre compte. » (not the queue's « Envoi dès le retour du réseau. »: the
    sheet is open, and the emulator answers an account missing from the device
    with such a failure); any other [Token d] → {!blocker}
    [(Denied d) ~online:true]; « Google Picker n’a pas pu s’ouvrir. »; « Le
    réglage n’a pas pu être enregistré. »; « Drive n’a pas répondu : réessayez.
    »; « Aucun compte Google sur le téléphone : ajoutez-en un dans les réglages
    d’Android. »; « Le choix du compte n’a pas pu s’ouvrir. Réessayez. »;
    [Other_account Offline] → « Pas de réseau : rien n’a changé. »;
    [Other_account (Consent_needed | Consent_refused)] → « L’autre compte n’a
    pas autorisé Google Drive : rien n’a changé. »; any other [Other_account _]
    → « L’autre compte n’a pas pu être utilisé : rien n’a changé. ». *)

type prompt = {text : string; action : string option  (** a button label *)}

val equal_prompt : prompt -> prompt -> bool

val drive_prompt :
  storage:Photo.Original_target.t -> pending:int -> access -> prompt option
(** The line under the « Dossier Drive » button; [None] when
    [storage = App_only] and [pending = 0] (no original waits for Drive; with
    [pending > 0], after « Les envoyer quand même », the photos still need
    Drive). Else: [Denied (Consent_needed | Consent_refused)] → « Google Drive
    n’est pas autorisé pour ce compte : les photos attendent sur le téléphone.
    Autorisez-le, ou changez de compte dans « Dossier Drive ». »,
    [Some "Autoriser"]; [Denied No_drive_account] → « Les photos attendent sur
    le téléphone : choisissez le compte et le dossier dans « Dossier Drive ». »,
    no action (the button is the action); [Denied No_account] /
    [Denied Misconfigured] → their {!blocker} text, no action; any other →
    [None]. *)

type dialog = {title : string; text : string}

val equal_dialog : dialog -> dialog -> bool

val stop_dialog : int -> dialog
(** Title and text of 4m's dialog when « Dans Herbier seulement » is chosen
    while [n > 0] originals wait on this phone: « 1 photo attend l’envoi vers
    Drive » / « 3 photos attendent l’envoi vers Drive », and « Sans envoi, leur
    original est effacé du téléphone ; la copie compressée reste. ». *)

type card = {title : string; detail : string}

val equal_card : card -> card -> bool

val has_drive_photo : Photo.t list -> bool
(** Some photo has [original_target = Drive]: {!saved_card} is [Some _]. *)

val saved_card :
  folder:folder ->
  access ->
  online:bool ->
  wifi_only:bool ->
  queued:Photo_id.t list ->
  Photo.t list ->
  card option
(** 4e's Drive card from the observation's photos: [None] when none has
    [original_target = Drive]. [queued]: the photos with a queue row ({!queue}'s
    [queued]). Title: « <n> photo(s) → Google Drive, dossier <folder_name
    folder> » (n = the Drive-bound photos). Detail, first that applies over
    them: all [Uploaded] → « Envoyée(s) dans Google Drive. Copies compressées
    gardées sur le téléphone. »; some [Original_missing] → « Original
    introuvable dans Google Drive : la copie compressée reste. »; some [Failed]
    with a queue row → « Échec de l’envoi : « Envoyer maintenant » dans
    Réglages. »; some [Failed] without one (its original could not be kept when
    it was saved) → « Original non conservé : la copie compressée reste. »;
    {!blocker}; [wifi_only] → « Envoi en Wi-Fi seulement. Copies compressées
    gardées sur le téléphone. »; some [Uploaded] → « <k> sur <n> envoyées. »;
    else « Envoi en cours. Copies compressées gardées sur le téléphone. ». *)

val viewer_badge : Photo.t -> string
(** 5e provenance: [Drive, Uploaded] → « Google Drive »;
    [Drive, (Pending | Failed)] → « ↑ en attente »; [Drive, Original_missing]
    and [App_only, _] → « local » (for a missing original, 5e says « original
    introuvable » on its own line, {!viewer_drive}). *)

type viewer_drive = Open of string  (** the file id *) | Missing | Hidden

val equal_viewer_drive : viewer_drive -> viewer_drive -> bool

val viewer_drive : Photo.t -> viewer_drive
(** [Drive, Uploaded] with a non-blank [drive_file_id] → [Open id] (trimmed);
    [Drive, Original_missing] → [Missing]; anything else → [Hidden]. *)
