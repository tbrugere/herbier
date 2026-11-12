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

(** {1 References} *)

type link_error =
  | Plant_gone  (** The plant is not live: nothing was written. *)
  | Store of Herbier_store.Db.error

val link :
  t ->
  Herbier_domain.Ids.Plant_id.t ->
  Herbier_refs.Sources.Gbif.Taxon.t ->
  (unit, link_error) result Fut.t
(** Links the plant to the taxon in one {!save}: [Plants.upsert] of
    {!Plant_link.apply},
    [References.link ~source:Gbif ~external_id:(string_of_int key)
     ~url:(Sources.Gbif.species_url key)], and, when the plant had another
    gbif_key, [References.remove] of each source of
    {!Herbier_refs.Fanout.sources} (whatever is live then). Reads the plant
    first: a plant not live → [Error Plant_gone], nothing written; a read or
    save error → [Error (Store _)]. Supersedes any fetch of that plant started
    earlier (its branches not yet saved are dropped; when the save fails, a
    fetch that was running is started again by {!refresh}), then, after the
    commit and when {!State.network} says online, starts the plant's fetch in
    the background (not awaited). {!saved} fires for the link and again for each
    branch saved. *)

val refresh : t -> Herbier_domain.Ids.Plant_id.t -> unit
(** ↻: fetches the plant's references now when {!State.network} says online, the
    plant is live, has a gbif_key and no fetch of it is running (else nothing).
    Read errors go to the console ([refs: …]), and so does the per-source
    report, as an error when a branch's save failed. *)

val refresh_if_due : t -> Herbier_domain.Ids.Plant_id.t -> unit
(** On opening the fiche: when {!State.network} says online and the plant has a
    gbif_key, starts its fetch as {!refresh} does if {!Herbier_refs.Fanout.due}
    [~now] holds for its rows. *)

val fetching : t -> Herbier_domain.Ids.Plant_id.t list React.signal
(** The plants with a fetch running (4f's « mise à jour… »), each once; set
    outside any update step when a fetch starts and ends. A primitive signal:
    releasing a screen's bindings on it never stops it. *)
