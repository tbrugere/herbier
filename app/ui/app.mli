(** The running app: the open database, the global {!State}, and the one place
    screens save synced rows through (local settings use
    {!Herbier_store.Db.write}). *)

type t

val create : db:Herbier_store.Db.t -> state:State.t -> t
val db : t -> Herbier_store.Db.t
val state : t -> State.t

val save :
  t ->
  Herbier_store.Outbox.edit list ->
  (int, Herbier_store.Db.error) result Fut.t
(** {!Herbier_store.Db.edit}: the edits and their outbox entries in one
    transaction. After a commit that appended at least one entry, {!saved} fires
    (outside any update step, once the future is determined). *)

val saved : t -> unit React.event
(** Something was saved: screens showing store data reload on it. *)
