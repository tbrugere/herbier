(** The device-only [uploads] table (architecture §3, §5): one row per original
    kept on this device for Drive, under [originals/<photo id>], until it is
    uploaded or abandoned. Not synced: written with
    {!Herbier_store_io.Db.write}, never [Db.edit], no outbox entry. A photo
    pulled from another install has no row here: only the install that holds the
    original uploads it. *)

module Photo_id := Herbier_domain.Ids.Photo_id

type session = {url : string; created_at : Ptime.t}
(** A Drive resumable session: [url] is a credential (valid a week), never
    logged. *)

type t = {
  photo_id : Photo_id.t;  (** primary key; foreign key to [photos], cascade *)
  path : string;  (** [Files.original photo_id] *)
  mime : string;
  size_bytes : int;  (** [>= 0] *)
  session : session option;  (** both columns null, or both set (a check) *)
  attempts : int;  (** [>= 0] *)
  last_error : string option;
  created_at : Ptime.t;
}

val equal : t -> t -> bool

val all : t Stmt.query
(** Every row, by [created_at] then [photo_id]. A stored row that does not
    decode is a [Decode] error (nothing skipped; a half-set session, ruled out
    by the table's check, reads as [None]). *)

val find : Photo_id.t -> t Stmt.query
(** The row of a photo: 0 or 1 row. *)

val put : t -> Stmt.t
(** [insert … on conflict (photo_id) do update set] every other column: 1
    change. *)

val remove : Photo_id.t -> Stmt.t
(** Deletes the row (a hard delete: the table is not synced): 1 or 0 changes. *)
