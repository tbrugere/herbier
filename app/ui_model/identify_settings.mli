(** 4m « Identification » (6h) and the gate of the Identifier buttons (6a, 6i,
    6k): the user's Pl@ntNet key (its rule and mask), the flora row and list,
    and their French texts. Pure; nothing here logs, and no value here prints
    the key (no [pp], no [show]). *)

val preferences_key : string
(** ["plantnet.api_key"]: the Capacitor Preferences key (never the SQLite
    settings table). *)

module Key : sig
  type t
  (** A non-blank Pl@ntNet API key. Abstract so that it is never printed by
      accident: no [pp] / [show] is derived. *)

  val of_input : string -> t option
  (** {!Herbier_domain.Text.non_blank}: trimmed (ASCII whitespace at both ends);
      blank → [None]. Inner characters are kept as typed. *)

  val to_string : t -> string
  (** The key itself, for [App.identify ~key], [App.floras ~key] and the
      Preferences write. Never log it, never show it. *)

  val equal : t -> t -> bool

  val masked : t -> string
  (** ["••••"] (four U+2022), then, when the key has at least 8 Unicode scalar
      values, a space (U+0020) and its last four scalar values:
      ["2b10AbCdEfGhIjKlMnOpQrStu"] → ["•••• rStu"]; ["abcdefgh"] →
      ["•••• efgh"]; ["abcdefg"] → ["••••"]; ["abcdefgé"] → ["•••• efgé"] (the
      last four counted in scalar values, never splitting a UTF-8 sequence). *)
end

type key =
  | Loading  (** not read from Preferences yet *)
  | Absent  (** no key stored (or a blank one, or the read failed) *)
  | Present of Key.t

val equal_key : key -> key -> bool

val key_of_stored : string option -> key
(** The key as Preferences gave it: [None] → [Absent]; [Some s] → [Present k]
    when [Key.of_input s] is [Some k], else [Absent]. *)

val key_detail : key -> string
(** The key row's value: [Loading] → ["…"] (U+2026); [Absent] → ["Aucune clé"];
    [Present k] → [Key.masked k]. *)

(** {1 The gate of the Identifier buttons} *)

type gate =
  | Ready of Key.t  (** a key and the network: a tap may send *)
  | Waiting  (** the key is still being read: disabled, no line *)
  | No_key  (** disabled, {!no_key_line} *)
  | Offline  (** disabled, the caller's offline line *)

val equal_gate : gate -> gate -> bool

val gate : key -> online:bool -> gate
(** [Loading] → [Waiting]; [Absent] → [No_key], online or not (the key line
    takes precedence over the offline one); [Present k] → [Ready k] online,
    [Offline] offline. *)

val no_key_line : string
(** ["Ajoutez votre clé API Pl@ntNet dans Réglages pour identifier."] *)

val opens_on_photo : on_photo:bool -> gate -> bool
(** Whether the session's first photo opens 6b: [on_photo] and [Ready _];
    [false] for every other gate (« Identifier dès la photo » does nothing
    without a key, offline, or while the key loads). *)

(** {1 The two SQLite settings} *)

type settings = {on_photo : bool; flora : Herbier_store.Settings.flora option}
(** « Identifier dès la photo » and « Flore Pl@ntNet » as the app starts with
    them. *)

val settings_of_stored :
  on_photo:bool option -> flora:Herbier_store.Settings.flora option -> settings
(** The stored values ([None]: unset or undecodable): [on_photo] unset → [true];
    [flora] as given ([None] = « Automatique »). *)

(** {1 Flora} *)

val automatic_title : string
(** ["Automatique"] *)

val flora_id : Herbier_store.Settings.flora option -> string
(** The flora a request asks for: [None] →
    {!Herbier_identify.Plantnet.automatic} (["all"]); [Some f] → [f.id]. *)

val flora_detail : Herbier_store.Settings.flora option -> string
(** The flora row's value: [None] → {!automatic_title}; [Some f] → [f.title]. *)

type flora_row = {
  detail : string;  (** {!flora_detail} of the stored choice, always *)
  note : string option;  (** why the list cannot open now *)
  enabled : bool;
}

val equal_flora_row : flora_row -> flora_row -> bool

val flora_row :
  key:key -> online:bool -> Herbier_store.Settings.flora option -> flora_row
(** In this order: [Loading] → disabled, no note; [Absent] → disabled,
    [Some "Ajoutez votre clé API Pl@ntNet pour choisir la flore."]; offline →
    disabled, [Some "Hors-ligne : la liste des flores demande le réseau."] (even
    when the session's list is cached); else enabled, no note. [detail] is the
    stored choice in every case. *)

type choice = {
  flora : Herbier_store.Settings.flora option;
      (** [None]: « Automatique »; the row's title is {!flora_detail} of it *)
  selected : bool;
}

val equal_choice : choice -> choice -> bool

val choices :
  current:Herbier_store.Settings.flora option ->
  Herbier_identify.Plantnet.project list ->
  choice list
(** « Automatique » ([flora = None]) first, then each project in Pl@ntNet's
    order as [Some {id; title}]; a project whose [id] is ["all"] is dropped («
    Automatique » is it); a second project with the same [id] is dropped (the
    first kept). [selected]: [current = None] → « Automatique » only;
    [current = Some f] → the entry whose id is [f.id] only, or none when the
    list no longer has it. *)

val filter : query:string -> choice list -> choice list
(** [query] blank (trimmed) → the list unchanged; else the first choice («
    Automatique ») kept, then those whose {!flora_detail} matches
    ({!Herbier_domain.Fold.matches}: case and accents ignored), order kept. *)

val flora_list_error : Herbier_identify.Plantnet.error -> string
(** The text under the open flora row when [App.floras] fails with [Plantnet e]:
    - [Key_refused] → ["Pl@ntNet a refusé la clé : vérifiez-la ci-dessous."]
    - [Quota_used_up] → ["Quota Pl@ntNet du jour atteint : réessayez demain."]
    - [Unreachable _] → ["Pl@ntNet injoignable : réessayez plus tard."]
    - [No_key] → ["Ajoutez votre clé API Pl@ntNet pour choisir la flore."]
    - [Key_not_exposed], [Refused_request _], [Malformed _], [No_plant],
      [No_photo] → {!flora_list_generic}.

    No text names CORS, an origin, localhost or exposing: the console line of
    [App.floras] names the class. *)

val flora_list_generic : string
(** ["La liste des flores n'a pas pu être chargée."] *)

val flora_list_offline : string
(** ["Hors-ligne : la liste des flores demande le réseau."] (the
    [Identify_offline] case; the same text as the row's offline note). *)

(** {1 Texts of 6h} *)

val section_title : string
(** ["Identification"] *)

val on_photo_label : string
(** ["Identifier dès la photo"] *)

val on_photo_detail : string
(** ["Pl@ntNet propose les espèces avant de nommer. En ligne seulement."] *)

val flora_title : string
(** ["Flore Pl@ntNet"] *)

val key_title : string
(** ["Clé API Pl@ntNet"] *)

val key_edit : string
(** ["Modifier"] *)

val key_placeholder : string
(** ["Collez votre clé API"] *)

val key_save : string
(** ["Enregistrer"] *)

val key_cancel : string
(** ["Annuler"] *)

val key_not_saved : string
(** ["Clé non enregistrée sur le téléphone."] *)

val key_help_before : string
(** ["Clé gratuite et personnelle, à créer sur "] *)

val key_help_link : string
(** ["my.plantnet.org"] *)

val key_help_url : string
(** ["https://my.plantnet.org/"] *)

val key_help_after : string
(** [". Dans votre compte Pl@ntNet, cochez « expose my API key » et ajoutez
     https://localhost aux domaines autorisés."] *)

val footnote : string
(** ["Pl@ntNet ne conserve pas les photos envoyées. Jusqu'à 500 identifications
     par jour."] *)

val search_placeholder : string
(** ["Flore"] *)

val loading : string
(** ["Chargement…"] *)

val retry : string
(** ["Réessayer"] *)

val selected_meta : string
(** ["Choisie"]: the meta line of the selected row *)
