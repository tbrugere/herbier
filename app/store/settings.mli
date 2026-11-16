(** The local [settings(key, value)] table (architecture §3): typed keys, values
    stored as text. Not synced. *)

type drive_folder = {id : string; name : string}
(** A Drive folder the user picked (4m « Dossier Drive »): its id and the name
    Drive gave when it was picked. *)

val equal_drive_folder : drive_folder -> drive_folder -> bool

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
      (** The Drive id of the root folder originals go into: either « Herbier »,
          found or created by the app ([Herbier_photos.Drive.resolve_root]), or
          the folder picked in 4m ({!Drive_root_folder_picked}); stored as the
          id's text, trimmed on read, a blank value refused ([Row `WrongType],
          read as unset); unset = find or create « Herbier » in My Drive's root
          at the next upload. *)
  | Drive_root_folder_picked : drive_folder key
      (** 4m « Dossier Drive »: the folder last picked with « Choisir ». Stored
          as compact JSON [{"id","name"}]. It is the root only while its [id]
          equals {!Drive_root_folder}'s value: an upload that replaced the root
          (picked folder trashed or gone) makes it stale without writing it. The
          [id] is trimmed on read; invalid JSON, a blank [id] or a missing
          [name] → [Row `WrongType] (read as unset). *)
  | Drive_root_folder_default : string key
      (** The {!Drive_root_folder} value that was in force before the current
          pick (the app's « Herbier », wherever the user moved it), restored by
          4m « Par défaut »; as {!Drive_root_folder}'s text; unset = none (« Par
          défaut » then finds or creates « Herbier » at My Drive's root). *)
  | Drive_account : string key
      (** 4m « Dossier Drive »: the email of the Google account Drive tokens are
          asked for. Trimmed on read; a blank value is refused
          ([Row `WrongType], read as unset). Unset = none chosen. Local only,
          never synced. Written with the root folder keys, in one transaction
          ({!drive_choice}, [Drive_root.forget_account]), or alone by
          [Drive_root.seed], which keeps the ids it finds (they are that
          account's). *)
  | Drive_account_changed_at : Ptime.t key
      (** When a choice in 4m « Dossier Drive » last stored a new
          {!Drive_account} (written with it by {!drive_choice}); as
          {!Codec.timestamp}; unset = never (an install's first account seeded
          from the session counts as no change). The health check takes a 404
          for a photo created before it as no answer
          ([Herbier_photos.Health.items]). Local only. *)

val name : _ key -> string
(** The stored key: ["storage_target"], ["wifi_only"],
    ["place_source_ign_offline"], ["place_source_ign_online"],
    ["place_source_photon_online"], ["location_notice_seen"],
    ["drive_health_checked_at"], ["last_upload_at"], ["drive_health_cursor"],
    ["drive_root_folder"], ["drive_root_folder_picked"],
    ["drive_root_folder_default"], ["drive_account"],
    ["drive_account_changed_at"]. *)

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
  root:string option ->
  picked:drive_folder option ->
  default:string option ->
  Stmt.t list
(** One 4m « Dossier Drive » choice, to run in one transaction:
    [account = Some e] → {!set} [Drive_account e] and
    [Drive_account_changed_at at] first ([None]: neither is written); then
    {!Drive_root_folder}, {!Drive_root_folder_picked} and
    {!Drive_root_folder_default}, each {!set} when [Some], {!unset} when [None].
*)
