(** The running app: the open database, the global {!State}, and the one place
    screens save synced rows through (local settings use
    {!Herbier_store.Db.write}). *)

type t

val create :
  db:Herbier_store.Db.t ->
  state:State.t ->
  theme:(Theme.t, Theme.error) result ->
  t
(** [theme]: {!Theme.load}'s result, read once at startup. *)

val db : t -> Herbier_store.Db.t
val state : t -> State.t

val theme : t -> (Theme.t, Theme.error) result
(** The design tokens OCaml needs (the map's colours), or why they are missing.
*)

val save :
  t ->
  Herbier_store.Outbox.edit list ->
  (int, Herbier_store.Db.error) result Fut.t
(** {!Herbier_store.Db.edit}: the edits and their outbox entries in one
    transaction. After a commit that appended at least one entry, {!saved} fires
    (outside any update step, once the future is determined). *)

val saved : t -> unit React.event
(** Something was saved: screens showing store data reload on it. *)

val save_photos :
  t ->
  observation:Herbier_domain.Observation.t ->
  Herbier_photos.Capture.shot list ->
  Herbier_photos.Capture.shot list Fut.t
(** Saves each shot's preview file and [pending] row
    ({!Herbier_photos.Preview.save}, with the preview made at capture and the
    storage setting of {!State.account}), one after the other, dated by its EXIF
    date or else now (a shutter shot is taken just before). Resolves to the
    shots that were not saved, in order, each failure logged; fires {!saved}
    once after the last when at least one was saved. The observation must
    already be stored. *)
