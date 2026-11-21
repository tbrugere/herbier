(** The local [settings(key, value)] table (architecture §3): typed keys, values
    stored as text. Not synced. *)

type flora = {id : string; title : string}
(** A Pl@ntNet flora as the list gave it: its id and French title. It mirrors
    [Herbier_identify.Plantnet.project], as store does not depend on identify.
*)

val equal_flora : flora -> flora -> bool

type _ key =
  | Storage_target : Herbier_domain.Photo.Original_target.t key
      (** 4m « Où vont mes photos »; stored as the enum label. *)
  | Wifi_only : bool key
      (** 4m « Envoyer seulement en Wi-Fi »; stored as ["true"] / ["false"]. *)
  | Place_source_ign_offline : bool key
      (** 4m « IGN hors-ligne »; ["true"] / ["false"]; unset = off. *)
  | Place_source_ign_online : bool key
      (** 4m « IGN en ligne »; ["true"] / ["false"]; unset = off. *)
  | Place_source_photon_online : bool key
      (** 4m « Photon en ligne »; unset = off. *)
  | Location_notice_seen : bool key
      (** The first-opening dialog was answered; unset = show it. *)
  | Drive_health_checked_at : Ptime.t key
      (** The last complete Drive health check ([Herbier_photos.Health]); stored
          as {!Codec.timestamp}; unset = never. *)
  | Last_upload_at : Ptime.t key
      (** 4m « Dernier envoi »: the last original this install put into Drive;
          {!Codec.timestamp}; unset = none yet. *)
  | Drive_health_cursor : Herbier_domain.Ids.Photo_id.t key
      (** The last photo the stopped Drive health round reached (answered or
          skipped, Health.report.reached); stored as the id's text; unset = the
          next round starts from the first photo. *)
  | Drive_root_folder : string key
      (** The Drive id of the root folder originals go into, found or created by
          the app under {!Drive_root_folder_name}
          ([Herbier_photos.Drive.resolve_root]), followed by id wherever the
          user moves it; stored as the id's text, trimmed on read, a blank value
          refused ([Row `WrongType], read as unset); unset = find or create the
          folder by name in My Drive's root at the next upload. *)
  | Drive_root_folder_name : string key
      (** 4m « Dossier Drive »: the name of the app's root folder, as last
          renamed in the app or read from Drive. Trimmed on read, a blank value
          refused ([Row `WrongType], read as unset). Unset = « Herbier ». Local
          only. Kept across a change of account. *)
  | Drive_account : string key
      (** 4m « Dossier Drive »: the email of the Google account Drive tokens are
          asked for. Trimmed on read; a blank value is refused
          ([Row `WrongType], read as unset). Unset = none chosen. Local only,
          never synced. Written with the root folder id, in one transaction
          ({!drive_choice}, [Drive_root.forget_account]), or alone by
          [Drive_root.seed], which keeps the id it finds (it is that account's).
      *)
  | Drive_account_changed_at : Ptime.t key
      (** When a choice in 4m « Dossier Drive » last stored a new
          {!Drive_account} (written with it by {!drive_choice}); as
          {!Codec.timestamp}; unset = never (an install's first account seeded
          from the session counts as no change). The health check takes a 404
          for a photo created before it as no answer
          ([Herbier_photos.Health.items]). Local only. *)
  | Identify_on_photo : bool key
      (** 4m « Identifier dès la photo »; ["true"] / ["false"]; unset = on. *)
  | Plantnet_project : flora key
      (** 4m « Flore Pl@ntNet »: compact JSON [{"id":…,"title":…}] (in that
          order); [id] and [title] trimmed on read, each non-blank; invalid
          JSON, not an object, a missing / non-string / blank [id] or [title] →
          [Row `WrongType] (read as unset). Unset = « Automatique » ([all]);
          choosing « Automatique » {!unset}s it. Local only, never synced. The
          Pl@ntNet key itself is never a setting (Capacitor Preferences). *)

val name : _ key -> string
(** The stored key: ["storage_target"], ["wifi_only"],
    ["place_source_ign_offline"], ["place_source_ign_online"],
    ["place_source_photon_online"], ["location_notice_seen"],
    ["drive_health_checked_at"], ["last_upload_at"], ["drive_health_cursor"],
    ["drive_root_folder"], ["drive_root_folder_name"], ["drive_account"],
    ["drive_account_changed_at"], ["identify_on_photo"], ["plantnet_project"].
*)

val get : 'a key -> 'a Stmt.query
(** 0 or 1 row: run it with [Db.find]. [None] means the key was never set, and
    the caller picks the default. A stored value that does not parse for the key
    ([Wifi_only] holding ["yes"], a target label a later version dropped) is a
    [Decode] error with [Row `WrongType]; the caller treats it as unset (uses
    the default, and {!set} overwrites it), so a bad value never locks a
    setting. *)

val set : 'a key -> 'a -> Stmt.t
(** Inserts or replaces the value of the key ([on conflict (key) do update]); 1
    change. *)

val unset : _ key -> Stmt.t
(** Deletes the key's row: 1 change when it was set, 0 otherwise. *)

val drive_choice :
  account:string option ->
  at:Ptime.t ->
  storage:Herbier_domain.Photo.Original_target.t option ->
  Stmt.t list
(** One Drive account choice (4m « Dossier Drive » or the Drive radio), to run
    in one transaction: [account = Some e] → {!set} [Drive_account e],
    [Drive_account_changed_at at], then {!unset} [Drive_root_folder] (the old
    Drive's id; {!Drive_root_folder_name} is kept); [None]: none of the three is
    touched. Then, when [storage = Some s], {!set} [Storage_target s] last.
    [None, None] → [[]]. *)
