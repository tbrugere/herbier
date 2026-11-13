(** The local [settings(key, value)] table (architecture §3): typed keys, values
    stored as text. Not synced. *)

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

val name : _ key -> string
(** The stored key: ["storage_target"], ["wifi_only"],
    ["place_source_ign_offline"], ["place_source_ign_online"],
    ["place_source_photon_online"], ["location_notice_seen"]. *)

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
