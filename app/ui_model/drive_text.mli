(** The Drive-related texts of 4e, 4m and 5e (architecture §5), from the photo
    rows, the upload queue's state and the Drive access. Pure: the screens and
    App compute the inputs. *)

module Photo := Herbier_domain.Photo
module Photo_id := Herbier_domain.Ids.Photo_id

(** Why no Drive token can be had (App maps [Herbier_sync.Auth.drive_error]). *)
type denial =
  | Unconfigured  (** a build without Google sign-in *)
  | Signed_out
  | Consent_needed
  | Consent_refused
  | Offline
  | Misconfigured
  | No_account
  | Failed  (** any other failure (Play Services, no plugin) *)

type access = Unknown | Granted | Denied of denial

val equal_access : access -> access -> bool

val access :
  account:Herbier_sync_core.Auth.Lifecycle.status -> last:access -> access
(** What the screens show from the auth status: [Unconfigured] →
    [Denied Unconfigured]; [Signed_out] → [Denied Signed_out]; [Restoring] →
    [Unknown]; [Signed_in _] → [last] (the last token outcome since this
    sign-in; a stale [Denied Signed_out] / [Denied Unconfigured] there reads as
    [Unknown]). *)

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
    « Envoi vers Drive indisponible dans cette version. »; [Denied Signed_out] →
    « Connectez-vous pour envoyer les photos. »;
    [Denied (Consent_needed | Consent_refused)] → « Google Drive n’est pas
    autorisé. »; [Denied No_account] → « Aucun compte Google sur le téléphone.
    »; [Denied Misconfigured] → « Google refuse l’accès à Drive (configuration
    de l’app). »; [not online] or [Denied (Offline | Failed)] → « Envoi dès le
    retour du réseau. »; else [None]. *)

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

val account_meta :
  email:string option -> storage:Photo.Original_target.t -> access -> string
(** 4m account card (signed in): the address (« Adresse inconnue » without),
    then « · Drive » when [storage = Drive] and [Granted]. *)

type prompt = {text : string; action : string option  (** a button label *)}

val equal_prompt : prompt -> prompt -> bool

val drive_prompt :
  storage:Photo.Original_target.t -> pending:int -> access -> prompt option
(** The row under the account card; [None] when [storage = App_only] and
    [pending = 0] (no original waits for Drive; with [pending > 0], after « Les
    envoyer quand même », the photos still need Drive). Else:
    [Denied (Consent_needed | Consent_refused)] → « Google Drive n’est pas
    autorisé : les photos attendent sur le téléphone. », [Some "Autoriser"];
    [Denied No_account] / [Denied Misconfigured] → their {!blocker} text, no
    action; [Denied Signed_out] → « Connectez-vous pour envoyer les photos vers
    Drive. », no action (the card's « Se connecter » is the action); any other →
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
  access ->
  online:bool ->
  wifi_only:bool ->
  queued:Photo_id.t list ->
  Photo.t list ->
  card option
(** 4e's Drive card from the observation's photos: [None] when none has
    [original_target = Drive]. [queued]: the photos with a queue row ({!queue}'s
    [queued]). Title: « <n> photo(s) → Google Drive, dossier Herbier » (n = the
    Drive-bound photos). Detail, first that applies over them: all [Uploaded] →
    « Envoyée(s) dans Google Drive. Copies compressées gardées sur le téléphone.
    »; some [Original_missing] → « Original introuvable dans Google Drive : la
    copie compressée reste. »; some [Failed] with a queue row → « Échec de
    l’envoi : « Envoyer maintenant » dans Réglages. »; some [Failed] without one
    (its original could not be kept when it was saved) → « Original non conservé
    : la copie compressée reste. »; {!blocker}; [wifi_only] → « Envoi en Wi-Fi
    seulement. Copies compressées gardées sur le téléphone. »; some [Uploaded] →
    « <k> sur <n> envoyées. »; else « Envoi en cours. Copies compressées gardées
    sur le téléphone. ». *)

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
