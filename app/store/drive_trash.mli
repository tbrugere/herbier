(** The device-only [drive_trash] table (architecture §3, §5): one row per
    original deleted in Herbier whose Drive file still has to go to Drive's bin.
    Filled in SQL by the trigger of migration 11 (a photo whose
    [original_target] is [Drive] and [drive_file_id] is set goes from live to
    deleted, by any write: a local delete or a pulled one) and by the upload
    queue ([Discard_uploaded]); emptied by the queue's passes once Drive
    answers. Not synced: written with {!Herbier_store_io.Db.write}, no outbox
    entry. *)

module Photo_id := Herbier_domain.Ids.Photo_id

type t = {
  photo_id : Photo_id.t;  (** primary key; foreign key to [photos], cascade *)
  file_id : string;  (** the Drive file to trash, never blank (a check) *)
  attempts : int;  (** [>= 0] *)
  last_error : string option;
  created_at : Ptime.t;
}

val equal : t -> t -> bool

val all : t Stmt.query
(** Every row, by [created_at] then [photo_id]. *)

val add : Photo_id.t -> file_id:string -> at:Ptime.t -> Stmt.t
(** [insert … on conflict (photo_id) do nothing], [attempts = 0], no error: 1
    change, or 0 when the photo already has a row (the trigger's, or an earlier
    add). *)

val put : t -> Stmt.t
(** [insert … on conflict (photo_id) do update set] every other column: 1
    change. *)

val remove : Photo_id.t -> Stmt.t
(** Deletes the row: 1 or 0 changes. *)
