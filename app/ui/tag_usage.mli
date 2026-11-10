(** Every live tag with the live plants carrying it, for 4l and 5d. *)

type t = {
  tag : Herbier_domain.Tag.t;
  plants : Herbier_domain.Ids.Plant_id.t list;
}

val load : Herbier_store.Db.t -> (t list, Herbier_store.Db.error) result Fut.t
(** In the store's tag order (name, case-insensitive); two queries. *)
