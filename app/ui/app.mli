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
    (outside any update step, once the future is determined) and
    {!geocode_pending} runs. *)

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
  ?name:string ->
  Herbier_domain.Ids.Plant_id.t ->
  Herbier_refs.Sources.Gbif.Taxon.t ->
  (unit, link_error) result Fut.t
(** Links the plant to the taxon in one {!save}: [Plants.upsert] of
    [Plant_link.apply ?name] (a free-name plant takes [name], its old name
    becoming an alias),
    [References.link ~source:Gbif ~external_id:(string_of_int key)
     ~url:(Sources.Gbif.species_url key)], and, when the plant had another
    gbif_key, [References.remove] of each source of
    {!Herbier_refs.Fanout.sources} and [References.unlink] of every other source
    than [Gbif] (the links pasted in 5a named the old taxon), whatever is live
    then. Reads the plant first: a plant not live → [Error Plant_gone], nothing
    written; a read or save error → [Error (Store _)]. Supersedes any fetch of
    that plant started earlier (its branches not yet saved are dropped; when the
    save fails, a fetch that was running is started again by {!refresh}), then,
    after the commit and when {!State.network} says online, starts the plant's
    fetch in the background (not awaited), followed by the thumbnail sync of
    {!refresh}. {!saved} fires for the link and again for each branch saved. *)

val create_linked :
  t ->
  ?extra:Herbier_store.Outbox.edit list ->
  Herbier_domain.Plant.t ->
  Herbier_refs.Sources.Gbif.Taxon.t ->
  (unit, Herbier_store.Db.error) result Fut.t
(** A new plant, not stored yet (from {!Plant_link.create}), in one {!save}:
    [Plants.upsert plant],
    [References.link ~source:Gbif ~external_id ~url:(Sources.Gbif.species_url
     key)], then [extra] in order (4k/5c: the observation's upsert onto the new
    plant). After the commit and when {!State.network} says online, starts the
    plant's fetch in the background followed by the thumbnail sync, as {!link}.
    A save error → [Error e], nothing written, no fetch. *)

val refresh : t -> Herbier_domain.Ids.Plant_id.t -> unit
(** ↻: fetches the plant's references now when {!State.network} says online, the
    plant is live, has a gbif_key and no fetch of it is running (else nothing).
    Read errors go to the console ([refs: …]), and so does the per-source
    report, as an error when a branch's save failed.

    After the fetch settles (whatever its report) and while {!State.network}
    says online, [Organ_thumbs.sync] runs for the plant; {!saved} fires when its
    report {!Herbier_refs_io.Organ_thumbs.changed}. At most one sync per plant
    runs at a time: one asked for while another runs starts once it ends. A
    non-empty report is logged as
    [refs: thumbs <plant id> flower downloaded leaf present …], as an error when
    a [Failed] is in it; a store error as [refs: thumbs <plant id> <error>]. *)

val refresh_if_due : t -> Herbier_domain.Ids.Plant_id.t -> unit
(** On opening the fiche: when {!State.network} says online and the plant has a
    gbif_key, starts its fetch as {!refresh} does if {!Herbier_refs.Fanout.due}
    [~now] holds for its rows. When the plant is not due and no fetch of it is
    running, [Organ_thumbs.sync] still runs (as after a fetch, see {!refresh}),
    so a thumbnail that failed earlier is retried on the next entry. *)

val fetching : t -> Herbier_domain.Ids.Plant_id.t list React.signal
(** The plants with a fetch running (4f's « mise à jour… »), each once; set
    outside any update step when a fetch starts and ends. A primitive signal:
    releasing a screen's bindings on it never stops it. *)

(** {1 Place names} *)

val geocode_pending : t -> unit
(** Fills [place_derived] in the background (architecture §8), online or not.
    When no run is going: reads [Observations.to_geocode] then
    [Observations.labelled] (a read error is logged, [geocode: read …], and ends
    the run), and for each pending observation in order (newest first), reading
    {!State.place_sources} and {!State.network} at that moment: runs
    [Place_name.resolve ~sources ~online ~labelled p] through [Geocoder.run],
    where [sources] is [Place_name.none] for an observation already tried at its
    current position this session (its own-place lookup still runs, its remote
    sources are not asked again);
    - [Ok (Named s)] → one [Observations.set_place_derived ~at:now] commit
      ({!saved} fires when it changed the row; unchanged → marked tried; a
      failed commit is logged, marks it tried and stops the run);
    - [Ok Unknown] → nothing written; when some online source was asked (i.e.
      [sources] had one on and [online]), marked tried and logged
      [geocode: <id> unknown] (a point no source was asked for logs nothing:
      with every source off that is every unnamed point, at every trigger);
    - [Ok Deferred] → nothing written, not marked; next observation;
    - [Error (Geocoder.Refused _)] (the request's source was turned off while it
      waited: [~allow] reads {!State.place_sources} when each request leaves the
      queue) → logged, not marked; next observation;
    - [Error e] → logged, the run stops; marked tried unless
      [Geocoder.transient e].

    Triggers: the app's start and the window's [online] event (main.ml), {!save}
    after a commit that changed rows, and {!set_place_source} turning a source
    on. A call during a run makes it read the lists again when it ends. No
    remote request is ever made for a source that is off. Never raises; nothing
    awaits it. *)

val settings_key :
  Herbier_geo.Place_name.source -> bool Herbier_store.Settings.key
(** The local setting of each source: [Place_source_ign_online],
    [Place_source_photon_online]. main.ml reads them at startup through it. *)

val set_place_source : t -> Herbier_geo.Place_name.source -> bool -> unit
(** A 4m switch: sets {!State.place_sources} at once (so a second tap while the
    write runs flips it back), then [Db.write] of its {!settings_key}.
    - Write ok → remembered as stored; clears {!place_error} when it is the
      source's latest write and the error shown is this source's (another
      source's success keeps it); when the value is [true], the session's tried
      list is cleared (a newly enabled source asks again for points tried with
      other sources) and {!geocode_pending} runs.
    - Write error → logged ([réglages: noms de lieux …]); when it is the
      source's latest write (an earlier one failing while a later one is queued
      changes nothing), State takes the stored value back, except that a failed
      [false] stays [false] for the session (an opt-out never fails open), and
      {!place_error} says so.

    Never raises. *)

val place_error : t -> string option React.signal
(** The last failed 4m source write, for 4m: « « <label> » : réglage non
    enregistré. Réessayez. », or, when a failed opt-out leaves the source off
    for the session while the stored value is still on, a text saying it will be
    on again at the next start. [None] after that source's next successful
    latest write; another source's success keeps it. A primitive signal. *)
