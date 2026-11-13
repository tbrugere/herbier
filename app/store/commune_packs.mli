(** The device-only [commune_packs] table (architecture §3): one row per
    downloaded département pack of « IGN hors-ligne » and its file under
    [communes/]. Not synced: written with {!Herbier_store_io.Db.write}, never
    through {!Herbier_store_io.Db.edit}, no outbox entry. Knows nothing of the
    pack's content. *)

type t = {
  departement : string;
      (** primary key, a code passing [Herbier_geo.Communes.Code.of_string] *)
  name : string;  (** the département's name, for 4m offline *)
  path : string;  (** [Files.commune_pack …] *)
  size_bytes : int;  (** byte length of the stored file *)
  communes : int;  (** number of communes in it, [> 0] *)
  downloaded_at : Ptime.t;
}

val equal : t -> t -> bool

val all : t Stmt.query
(** Every row, ordered by [departement]. A stored row that does not decode is a
    [Decode] error (nothing skipped). *)

val find : string -> t Stmt.query
(** The row of a département code: 0 or 1 row. *)

val put : t -> Stmt.t
(** [insert … on conflict (departement) do update set name, path, size_bytes,
     communes, downloaded_at]: 1 change. *)

val remove : departement:string -> Stmt.t
(** Deletes the row (a hard delete: the table is not synced): 1 or 0 changes. *)
