(** Every live tag with the live plants carrying it, for 4l. *)

type t = {
  tag : Herbier_domain.Tag.t;
  plants : Herbier_domain.Ids.Plant_id.t list;
}

val load :
  Herbier_store_io.Db.t -> (t list, Herbier_store_io.Db.error) result Fut.t
(** In the store's tag order (name, case-insensitive); two queries. *)

val counts : t list -> (Herbier_domain.Tag.t * int) list
(** Each tag with the number of plants carrying it, in the same order: what
    {!Herbier_ui_model.Tag_pick.suggestions} reads. *)
