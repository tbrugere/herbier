(** The writes of a synced table whose rows are read back by [id] (plants,
    observations, photos, tags): the edits every such table shares. *)

module type TABLE = sig
  type table
  type id
  type row

  val table : table Postgrest.Col.table
  val id : (table, id, [`Mandatory]) Postgrest.Col.t
  val row : (table, row) Postgrest.Row.t
  val id_of : row -> id

  val id_to_string : id -> string
  (** The outbox entry's [row_id]. *)

  val input : row -> (table, [`Full]) Postgrest.Input.t
end

module Make (T : TABLE) : sig
  val reread : T.id -> T.row Stmt.query
  (** [select * from <table> where id = ?], whatever [deleted_at]: a soft delete
      must read back the row it deleted. *)

  val edit : T.id -> Stmt.t -> Outbox.edit
  (** {!Outbox.edit} of a statement on the row [id], read back by {!reread}. *)

  val upsert : T.row -> Outbox.edit
  (** {!Stmt.upsert} of the whole row ([input]), read back by its [id]. *)

  val soft_delete : T.id -> at:Ptime.t -> Outbox.edit
  (** {!Stmt.soft_delete} of the row [id], read back by [id]. *)
end
