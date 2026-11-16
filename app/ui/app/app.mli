(** The running app: the open database, the global {!State}, the account
    ({!Herbier_sync.Auth}), the sync engine ({!Herbier_sync.Engine}), and the
    one place screens save synced rows through (local settings use
    {!Herbier_store_io.Db.write}). *)

type t

val create :
  db:Herbier_store_io.Db.t ->
  state:State.t ->
  theme:(Theme.t, Theme.error) result ->
  auth:Herbier_sync.Auth.t ->
  t
(** [theme]: {!Theme.load}'s result, read once at startup. [auth] is not started
    here (see {!start_auth}); the sync engine is built but not started (see
    {!start_sync}), and so is the keep-alive's side ({!keepalive}, started by
    {!start_keepalive}). No IO. *)

val db : t -> Herbier_store_io.Db.t
val state : t -> State.t
val auth : t -> Herbier_sync.Auth.t

val start_auth : t -> unit
(** {!Herbier_sync.Auth.start} with an [on_change] that sets {!State.account}'s
    [auth] (keeping the other fields), outside any update step, and on a change
    to [Signed_in {email}] sends {!Herbier_sync.Engine.signed_in}; then, with no
    Drive account stored and a Drive folder id set,
    [Drive_root.seed ~session_email:email] inside [Upload_queue.exclusive]
    stores that email as the Drive account (an older install's folders stay with
    the account its tokens named); then runs {!upload_pending},
    {!check_drive_access} and {!check_originals} (each gated on its own
    conditions). Otherwise the session does not change the Drive account, which
    is 4m « Dossier Drive »'s. Called once by main; dev pages never call it, so
    that the apps they build register no app-state listener and no timer. *)

val start_sync : t -> unit
(** {!Herbier_sync.Engine.start}: called once by main, right after
    {!start_auth}. Until then the engine ignores every trigger. *)

val engine : t -> Herbier_sync.Engine.t
(** For #dev/sync. *)

val keepalive : t -> Herbier_sync.Keepalive.t
(** The keep-alive job's side in the app, built by {!create} and wired to the
    engine's push ({!Herbier_sync.Keepalive.before_push},
    {!Herbier_sync.Keepalive.hand_off}). For #dev/keepalive. *)

val start_keepalive : t -> unit
(** [Auth.on_job_session]: [Granted s] → [Keepalive.replace_session s];
    [Dropped] → [Keepalive.drop_session]. Failures are logged by
    {!Herbier_sync.Keepalive}. Called once by main, after {!start_sync}; dev
    pages never call it. *)

val start_uploads : t -> unit
(** Once, by main, after {!start_keepalive}: a silent pass of the originals'
    queue now ([Upload_queue.run ~interactive:false]), and one on every resume
    ([Cap_app.on_state_change Active]) and every change of an upload job
    ([Cap_uploader.on_change]); [Upload_queue.wifi_changed] on every change of
    {!State.account}'s [wifi_only] (the binding kept reachable by the app). It
    also reads {!upload_queue} once, re-reads it after every pass it runs, and
    runs {!check_originals} now and on every resume. Registration failures are
    console lines (in a browser: no uploader). Sign-in ({!start_auth}) and the
    network ({!upload_pending}) run passes too. Dev pages never call it. *)

val upload_pending : t -> unit
(** A silent pass of the originals' queue, then the {!upload_queue} read; not
    awaited (sign-in, main's online event). *)

val uploads : t -> Herbier_photos_io.Upload_queue.t
(** The originals' queue (architecture §5). For #dev/uploader. *)

(** {1 Drive} *)

val drive_access : t -> Herbier_ui_model.Drive_text.access React.signal
(** {!Herbier_ui_model.Drive_text.access} of {!State.account}'s [drive] and the
    last Drive token outcome for the chosen account: every [Auth.drive_token]
    the app asks for the stored account (the queue's, the health check's,
    {!check_drive_access}, {!authorize_drive}, the sheet's when it names the
    stored account) sets it ([Ok _] → [Granted]; [Error e] → [Denied] of e
    mapped: [Drive_unconfigured] → [Unconfigured], [Drive_no_account] →
    [No_drive_account], [Consent_needed], [Consent_refused], [Drive_offline] →
    [Offline], [Drive_misconfigured] → [Misconfigured], [No_google_account] →
    [No_account], [Drive_google _] → [Failed]); a change of the Drive account
    resets it to [Unknown]. Set outside any update step. *)

val check_drive_access : t -> unit
(** A silent [Auth.drive_token ~interactive:false] when a Drive account is
    chosen and the storage is Drive, or photos still wait in the {!upload_queue}
    (its [pending_count > 0], after « Les envoyer quand même ») (4m's mount,
    after a sign-in, the radio set to Drive); else nothing. Not awaited. *)

val authorize_drive : t -> unit
(** 4m « Autoriser »: [Auth.drive_token ~interactive:true] (the consent), then,
    on [Ok], {!upload_pending}. Not awaited. *)

val upload_queue : t -> Herbier_ui_model.Drive_text.queue React.signal
(** The originals' queue as 4m and 4e show it: [Upload_queue.entries] and
    [Settings.get Last_upload_at] read again after every pass (resume, job
    change, sign-in, online, Wi-Fi setting, {!save_photos}' keep), {!send_now}
    and {!stop_drive_uploads}. 4d's « N en attente » is its
    {!Herbier_ui_model.Drive_text.pending_count}. A read error is a console line
    and keeps the last value. Starts at
    {!Herbier_ui_model.Drive_text.empty_queue}; read once by {!start_uploads}.
*)

val drive_folder : t -> Herbier_ui_model.Drive_text.folder React.signal
(** Where originals go (4m « Dossier Drive », 4e's card):
    [Drive_root.read_choice] through {!Herbier_ui_model.Drive_text.folder}, read
    by {!start_uploads}, after every pass (a pass may store or forget the root),
    and after {!store_pick} and {!store_default}. A read error is a console line
    and keeps the last value. Starts [Default]. *)

val picker_config : Herbier_ui_model.Drive_text.picker_config
(** {!Herbier_ui_model.Drive_text.picker_config_of_project_number} of
    {!Herbier_sync.Backend.google_cloud_project_number}. No API key is passed
    (notes/google-picker-webview.md). *)

val choose_account :
  unit ->
  (string, Herbier_sync_core.Auth.Drive_account.choose_error) result Fut.t
(** The sheet's account choice: [Auth.choose_drive_account] (Credential
    Manager's « Sign in with Google » chooser). Nothing is stored. *)

val folder_token :
  t -> email:string -> (string, Herbier_ui_model.Drive_text.denial) result Fut.t
(** The sheet's interactive drive.file token for [email] (the consent when
    needed): [Core.drive_token_for ~interactive:true], recorded into
    {!drive_access} only when [email] is the stored account; an error mapped as
    {!drive_access} does. *)

val open_picker :
  t ->
  Herbier_bindings.Google_picker.ticket ->
  account:string ->
  token:string ->
  ( Herbier_bindings.Google_picker.outcome,
    Herbier_ui_model.Drive_text.pick_error )
  result
  Fut.t
(** Google Picker on the folders for [account]'s [token]
    ([Google_picker.pick_folder], app id the project number, no key, origin
    [window.location.origin], title {!Herbier_ui_model.Drive_sheet.picker_title}
    of [account]: the Picker shows the token's account and has no switcher of
    its own). [Load_failed] while offline → [Offline], any other error →
    [Picker_unavailable]. A ticket dismissed (leaving the sheet) →
    [Ok Cancelled]. *)

val store_pick :
  t ->
  account:string ->
  Herbier_store.Settings.drive_folder ->
  (unit, Herbier_ui_model.Drive_text.pick_error) result Fut.t
(** The sheet's pick for [account] (possibly not stored yet), inside
    [Upload_queue.exclusive] (no pass reads or writes the root meanwhile; a
    raise → [Drive_failed]): [Photos_io.Drive.folder_info] of its id with
    [account]'s silent token: [Usable {id; name}] →
    [Drive_root.choose ~account {id; name}] (Drive's name, not the Picker's;
    account and folder in one write; a new account forgets the old one's root,
    picked and default folders; a write error → [Not_saved]); [Not_a_folder],
    [Folder_trashed], [No_access] → their error, nothing written; a token error
    → [Token]; [Network] → [Offline]; any other Drive error → [Drive_failed]. On
    [Ok], {!State.account}'s [drive] := [Chosen account]
    ([Core.set_drive_account]: a new account resets {!drive_access}'s last
    outcome). Then the {!drive_folder} read, and on [Ok], {!upload_pending} and
    {!check_originals}: originals not started yet go to the new folder; an
    upload whose resumable session already started finishes where it began (the
    parent and the account are fixed when the session starts). Never raises. *)

val store_default :
  t ->
  account:string ->
  (unit, Herbier_ui_model.Drive_text.pick_error) result Fut.t
(** The sheet's « Par défaut » for [account]: inside [Upload_queue.exclusive],
    [Drive_root.reset ~account] (an error or a raise → [Not_saved]), then as
    {!store_pick} after its write. *)

val forget_account : t -> (unit, Herbier_store_io.Db.error) result Fut.t
(** #dev/drive « Oublier le compte »: inside [Upload_queue.exclusive],
    [Drive_root.forget_account] (the account and the three root keys in one
    transaction; a raise → [Error (Raised _)]); on [Ok], {!State.account}'s
    [drive] := [Unchosen] ([Core.set_drive_account]). Then the {!drive_folder}
    read. *)

val send_now : t -> unit
(** [Upload_queue.send_now], then the {!upload_queue} read. Not awaited. *)

val stop_drive_uploads : t -> (unit, Herbier_store_io.Db.error) result Fut.t
(** [Upload_queue.stop_drive] (its outcome), then the {!upload_queue} read. *)

val set_storage :
  t ->
  Herbier_domain.Photo.Original_target.t ->
  (unit, Herbier_store_io.Db.error) result Fut.t
(** The 4m radio: [Db.write (Settings.set Storage_target target)], then
    {!State.account}'s [storage] (a write error is a console line, changes
    nothing and is the result); a choice of [Drive] also runs
    {!check_drive_access}. *)

val health : t -> Herbier_photos_io.Health.t
(** The Drive health check, its token silent and recorded into {!drive_access}.
    For #dev/drive. *)

val check_originals : t -> unit
(** [Health.run ~force:false] when {!State.network} says online and a Drive
    account is chosen; not awaited. Triggers: {!start_uploads} (startup), resume
    ([Cap_app] Active), a change to [Signed_in] ({!start_auth}), a Drive account
    or folder stored by the 4m sheet ({!store_pick}, {!store_default}), and
    main's [online] event. Not on job changes. *)

val synced : t -> unit React.event
(** Fires after every sync cycle, outside any update step. *)

val theme : t -> (Theme.t, Theme.error) result
(** The design tokens OCaml needs (the map's colours), or why they are missing.
*)

val save :
  t ->
  Herbier_store.Outbox.edit list ->
  (int, Herbier_store_io.Db.error) result Fut.t
(** {!Herbier_store_io.Db.edit}: the edits and their outbox entries in one
    transaction. After a commit that appended at least one entry, {!saved} fires
    and the sync engine gets a local write (outside any update step, once the
    future is determined), and {!geocode_pending} runs. *)

val saved : t -> unit React.event
(** The store changed (a local save, or a pull that wrote rows): screens showing
    store data reload on it. *)

val save_photos :
  t ->
  observation:Herbier_domain.Observation.t ->
  Herbier_photos_io.Capture.shot list ->
  Herbier_photos_io.Capture.shot list Fut.t
(** Saves each shot's preview file and [pending] row
    ({!Herbier_photos_io.Preview.save}, with the preview made at capture and the
    storage setting of {!State.account}), one after the other, dated by its EXIF
    date or else now (a shutter shot is taken just before). A saved photo bound
    for Drive has its original kept for upload ([Upload_queue.keep]); a keep
    that fails is logged and the photo committed [Failed] (its original is
    gone). Resolves to the shots that were not saved, in order, each failure
    logged; fires {!saved} and sends the engine a local write once after the
    last when at least one was saved; when at least one original was kept,
    starts an interactive pass of the queue (not awaited: the first Drive photo
    may show the drive.file consent). The observation must already be stored. *)

(** {1 References} *)

type link_error =
  | Plant_gone  (** The plant is not live: nothing was written. *)
  | Store of Herbier_store_io.Db.error

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
  (unit, Herbier_store_io.Db.error) result Fut.t
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

(** {1 Données hors-ligne} *)

val offline_usage :
  unit ->
  (Herbier_ui_model.Offline_data.usage, Herbier_bindings.Cap_error.t) result
  Fut.t
(** 4m's sizes: [Files.usage] of the previews' directory, then of the reference
    thumbnails' one; the first error. Not cached: 4m reads it when it opens and
    after « Libérer ». *)

type free_error =
  | Busy  (** a thumbnail sync or another « Libérer » is running *)
  | Store of Herbier_store_io.Db.error
      (** clearing the rows failed; files untouched *)
  | Files of Herbier_bindings.Cap_error.t
      (** rows cleared, removing the files failed *)

val free_reference_photos : t -> (unit, free_error) result Fut.t
(** « Libérer »: [Error Busy], nothing done, while a thumbnail sync (see
    {!refresh}) or another « Libérer » runs. Otherwise, while it runs, the
    thumbnail syncs asked for are skipped (not queued: the next fiche entry asks
    again); it clears every [thumb_path] ([Ref_images.clear_thumbs]; an error is
    [Error (Store _)], files untouched), then removes the thumbnails' directory
    (an error is [Error (Files _)]: the rows are already cleared, the files left
    are overwritten by the next downloads). On [Ok], {!saved} fires (an open 4f
    drops its organ tiles). One console line, [offline: freed reference photos]
    or the error. Never raises. *)

(** {1 Place names} *)

val geocode_pending : t -> unit
(** Fills [place_derived] in the background (architecture §8), online or not.
    When no run is going: waits for the startup load of the « IGN hors-ligne »
    packs (see {!packs}), reads [Observations.to_geocode] then
    [Observations.labelled] (a read error is logged, [geocode: read …], and ends
    the run), and for each pending observation in order (newest first), reading
    {!State.place_sources} and {!State.network} at that moment: runs
    [Place_name.resolve ~sources ~online ~labelled ~communes p] through
    [Geocoder.run], [communes] the packs' index at that moment, where [sources]
    is [Place_name.offline_only] of the switches for an observation already
    tried at its current position this session (its own-place and pack lookups
    still run, its remote sources are not asked again);
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
    after a commit that changed rows, {!set_place_source} turning a source on,
    and {!download_pack} succeeding while « IGN hors-ligne » is on. A call
    during a run makes it read the lists again when it ends. No remote request
    is ever made for a source that is off. Never raises; nothing awaits it. *)

val settings_key :
  Herbier_geo.Place_name.source -> bool Herbier_store.Settings.key
(** The local setting of each source: [Place_source_ign_offline],
    [Place_source_ign_online], [Place_source_photon_online]. main.ml reads them
    at startup through it. *)

val set_place_source : t -> Herbier_geo.Place_name.source -> bool -> unit
(** A 4m switch: sets {!State.place_sources} at once (so a second tap while the
    write runs flips it back), then [Db.write] of its {!settings_key}.
    - Write ok → remembered as stored; clears {!place_error} when it is the
      source's latest write and the error shown is this source's (another
      source's success keeps it); when the value is [true], {!geocode_pending}
      runs, after clearing the session's tried list when the source
      [Place_name.is_online] (a newly enabled online source asks again for
      points tried with other sources; the offline one is asked for them
      anyway).
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

(** {1 « IGN hors-ligne » packs} *)

type pack = {
  code : Herbier_geo.Communes.Code.t;
  row : Herbier_store.Commune_packs.t;  (** [row.departement] is [code] *)
  usable : bool;
}

val equal_pack : pack -> pack -> bool

val packs : t -> pack list React.signal
(** The downloaded packs, in département order; [usable = false] when its file
    did not load ({!Herbier_geo_io.Commune_packs.load}, started by {!create} in
    the background; a failed load is logged and leaves []). A primitive signal;
    [] until the load ends. *)

type pack_error =
  | Busy  (** another download runs, or this pack is being downloaded *)
  | Offline  (** {!State.network} says offline: nothing was sent *)
  | Pack of Herbier_geo_io.Commune_packs.error

val pack_error_to_string : pack_error -> string
(** French, for 4m: « Un téléchargement est déjà en cours. » ([Busy]), «
    Hors-ligne : réessayez une fois connecté. » ([Offline], [Network],
    [Timeout]), « Service de l’IGN indisponible : réessayez plus tard. » (a
    [Status] that is [Geocoder.transient]: 429, 5xx), « Réponse de l’IGN
    inattendue. » ([Payload], any other [Status]), « Enregistrement impossible.
    » ([File], [Store]), « Téléchargement non envoyé. Réessayez. » ([Refused],
    which no download asks for). *)

val departements :
  t -> (Herbier_geo.Communes.departement list, pack_error) result Fut.t
(** 4m's picker list ({!Herbier_geo_io.Commune_packs.departements}, its error as
    [Pack]); offline per {!State.network} → [Error Offline] with no request. *)

val downloading : t -> Herbier_geo.Communes.departement option React.signal
(** The département being downloaded, from the tap to the end; one download at a
    time. A primitive signal. *)

val download_pack :
  t -> Herbier_geo.Communes.departement -> (unit, pack_error) result Fut.t
(** [Busy] while {!downloading} is [Some _]. Else {!downloading} is set at once,
    and once the startup load of the packs has ended (it replaces the index and
    {!packs} wholesale), {!Herbier_geo_io.Commune_packs.download}; on success,
    in one step, {!packs} gains the row (usable, replacing one of the same code)
    and {!downloading} returns to [None], the index gains the pack; then, when «
    IGN hors-ligne » is off, [set_place_source t Ign_offline true] (which runs
    {!geocode_pending}), else {!geocode_pending}. An error is logged
    ([communes: download …]). Never raises. *)

val delete_pack :
  t -> Herbier_geo.Communes.Code.t -> (unit, pack_error) result Fut.t
(** [Busy] while that code is downloading. Else
    {!Herbier_geo_io.Commune_packs.delete}; on success the index and {!packs}
    drop it. Names already stored stay (a [place_derived] is a snapshot); the
    switch is not touched. An error is logged ([communes: delete …]). Never
    raises. *)
