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
  identification:Herbier_ui_model.Identify_settings.settings ->
  t
(** [theme]: {!Theme.load}'s result, read once at startup. [identification]: «
    Identifier dès la photo » and « Flore Pl@ntNet » as main read them from the
    settings table before building the app; the Pl@ntNet key is read later
    ({!load_plantnet_key}). [auth] is not started here (see {!start_auth}); the
    sync engine is built but not started (see {!start_sync}), and so is the
    keep-alive's side ({!keepalive}, started by {!start_keepalive}). No IO. *)

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
(** The originals' queue as 4m and 4h show it: [Upload_queue.entries] and
    [Settings.get Last_upload_at] read again after every pass (resume, job
    change, sign-in, online, Wi-Fi setting, {!save_photos}' keep), {!send_now}
    and {!stop_drive_uploads}. 4d's « N en attente » is its
    {!Herbier_ui_model.Drive_text.pending_count}. A read error is a console line
    and keeps the last value. Starts at
    {!Herbier_ui_model.Drive_text.empty_queue}; read once by {!start_uploads}.
*)

val drive_folder : t -> string React.signal
(** The root folder's name (4m « Dossier Drive », 4h's card): the stored
    [drive_root_folder_name] as [Drive_root.root] reads it (« Herbier » when
    unset), read by {!start_uploads}, after every pass (a pass may store the
    name Drive gave), and after {!store_account} and {!rename_folder}. A read
    error is a console line and keeps the last value. Starts « Herbier ». *)

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

val store_account :
  t ->
  account:string ->
  turn_on:bool ->
  (unit, Herbier_ui_model.Drive_text.sheet_error) result Fut.t
(** The sheet's other account, or 4m's Drive radio ([turn_on = true]), once its
    drive.file token was granted: inside [Upload_queue.exclusive] (no pass reads
    or writes the root meanwhile; a raise → [Not_saved]),
    [Drive_root.store_account ~account ~storage] with [storage = Some Drive] iff
    [turn_on] (a new account and its time stored, the old Drive's root id
    forgotten, the folder name kept, the storage in the same transaction; a
    write error → [Not_saved], nothing written). No Drive request: the folder is
    created at the first upload or by a rename. On [Ok], {!State.account}'s
    [drive] := [Chosen account] ([Core.set_drive_account]: a new account resets
    {!drive_access}'s last outcome). Then the {!drive_folder} read, and on [Ok],
    {!State.account}'s [storage] := [Drive] when [turn_on] (then
    {!check_drive_access} for that account), {!upload_pending} and
    {!check_originals}: originals not started yet go to the new account's Drive;
    an upload whose resumable session already started finishes where it began.
    Never raises. *)

val rename_folder :
  t ->
  account:string ->
  name:string ->
  (string, Herbier_ui_model.Drive_text.sheet_error) result Fut.t
(** The sheet's « Renommer » with the stored Drive [account]: a blank [name]
    ([Herbier_photos.Drive.folder_name] [None]) → [Error Blank_name], nothing
    sent or written. Else inside [Upload_queue.exclusive] (a raise →
    [Drive_failed]): [Drive_root.run] of [Photos_io.Drive.rename_root] with
    [account]'s interactive token (files.update of the stored root; a root gone
    or none stored → a folder under the new name found or created at My Drive's
    root; the root id and the name Drive answered stored by [Drive_root.apply]).
    [Ok n]: the name Drive now has, stored. Errors: a settings read error →
    [Not_saved]; a token error → [Token]; [Network] → [Offline]; any other Drive
    error → a console line and [Drive_failed]. Then the {!drive_folder} read,
    also on an error; an [Ok n] whose [n] that read does not give (the settings
    write failed) → a console line and [Not_saved]. Never raises. *)

val forget_account : t -> (unit, Herbier_store_io.Db.error) result Fut.t
(** #dev/drive « Oublier le compte »: inside [Upload_queue.exclusive],
    [Drive_root.forget_account] (the account and the root folder id in one
    transaction, the name kept; a raise → [Error (Raised _)]); on [Ok],
    {!State.account}'s [drive] := [Unchosen] ([Core.set_drive_account]). Then
    the {!drive_folder} read. *)

val send_now : t -> unit
(** [Upload_queue.send_now], then the {!upload_queue} read. Not awaited. *)

val stop_drive_uploads : t -> (unit, Herbier_store_io.Db.error) result Fut.t
(** [Upload_queue.stop_drive] (its outcome), then the {!upload_queue} read. *)

val set_storage :
  t ->
  Herbier_domain.Photo.Original_target.t ->
  (unit, Herbier_store_io.Db.error) result Fut.t
(** [Db.write (Settings.set Storage_target target)], then {!State.account}'s
    [storage] (a write error is a console line, changes nothing and is the
    result); a choice of [Drive] also runs {!check_drive_access}. From 4m,
    [Drive] goes through {!store_account} [~turn_on:true], so the storage is
    never Drive without an account. *)

val health : t -> Herbier_photos_io.Health.t
(** The Drive health check, its token silent and recorded into {!drive_access}.
    For #dev/drive. *)

val check_originals : t -> unit
(** [Health.run ~force:false] when {!State.network} says online and a Drive
    account is chosen; not awaited. Triggers: {!start_uploads} (startup), resume
    ([Cap_app] Active), a change to [Signed_in] ({!start_auth}), a Drive account
    stored by 4m ({!store_account}), and main's [online] event. Not on job
    changes. *)

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
    future is determined), {!geocode_pending} runs, and so does
    {!upload_pending} (a delete's cancelled uploads and Drive-bin rows). *)

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
    fetch of every source ([Herbier_refs.Fetch_rule.decide Linked]) in the
    background (not awaited), followed by the thumbnail sync of {!refresh};
    offline, {!fetch_pending_references} fetches it when the network returns if
    a source is unfinished ([Herbier_refs.Fetch_rule.unfinished]). {!saved}
    fires for the link and again for each branch saved. *)

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
    plant's fetch of every source in the background followed by the thumbnail
    sync, as {!link} (offline: {!fetch_pending_references}, when the network
    returns). A save error → [Error e], nothing written, no fetch. *)

val refresh : t -> Herbier_domain.Ids.Plant_id.t -> unit
(** ↻: fetches the plant's references now when {!State.network} says online, the
    plant is live, has a gbif_key and no fetch of it is running (else nothing).
    Read errors go to the console ([refs: …]), and so does the per-source
    report, as an error when a branch's save failed.

    As soon as the Pl@ntNet branch's row is written, and again after the fetch
    settles (whatever its report), while {!State.network} says online,
    [Organ_thumbs.sync] runs for the plant; {!saved} fires when its report
    {!Herbier_refs_io.Organ_thumbs.changed}. At most one sync per plant runs at
    a time: one asked for while another runs starts once it ends. A non-empty
    report is logged as
    [refs: thumbs <plant id> flower downloaded leaf present …], as an error when
    a [Failed] is in it; a store error as [refs: thumbs <plant id> <error>]. *)

val refresh_if_due : t -> Herbier_domain.Ids.Plant_id.t -> unit
(** On opening the fiche: when {!State.network} says online and the plant has a
    gbif_key, starts its fetch as {!refresh} does if {!Herbier_refs.Fanout.due}
    [~now] or [Herbier_refs.Fetch_rule.unfinished] holds for its rows (a failed
    source is retried after a few minutes). When the plant is not due and no
    fetch of it is running, [Organ_thumbs.sync] still runs (as after a fetch,
    see {!refresh}), so a thumbnail that failed earlier is retried on the next
    entry. Decided by [Herbier_refs.Fetch_rule.decide Opened]. *)

val fetch_pending_references : ?back_online:bool -> t -> unit
(** The reconnect pass, [back_online] (default [false]) when the network came
    back, at startup without it: when {!State.network} says online and no pass
    is running, reads [Plants.list] and [References.fetch_states] (no payload),
    and fetches each plant of [Herbier_refs.Fetch_rule.pending ~back_online] one
    after the other (each as {!refresh} does, thumbnail sync included). At its
    turn the plant is read again: one deleted, unlinked or linked to another key
    since the pass began is skipped, and so is one whose
    [Fetch_rule.decide Reconnected] is not [Fetch] (running, finished
    meanwhile); the pass stops at the first plant found offline. A pass asked
    for while one runs runs once more after it (as a [back_online] one). Read
    errors are a console line ([refs: pending], [refs: read]). Logs
    [refs: pending <n>] when n > 0. Never raises. *)

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
(** Fills [place_derived] and [place_detail] in the background (architecture
    §8), online or not, and renames once the observations named before the
    commune-first rule. When no run is going: waits for the startup load of the
    « IGN hors-ligne » packs (see {!packs}), reads [Observations.to_geocode],
    [Observations.to_rename] then [Observations.labelled] (a read error is
    logged, [geocode: read …], and ends the run), and for each pending
    observation in order (newest first), then each one to rename (newest first),
    reading {!State.place_sources} and {!State.network} at that moment: runs
    [Place_name.resolve ~sources ~online ~labelled ~communes p] through
    [Geocoder.run], [communes] the packs' index at that moment, where [sources]
    is [Place_name.offline_only] of the switches for an observation already
    tried at its current position this session (its own-place and pack lookups
    still run, its remote sources are not asked again);
    - [Ok (Named n)] → one commit at [~at:now]: for a pending one
      [Observations.set_place_derived ~detail:n.detail n.name] (unchanged →
      marked tried); for one to rename
      [Observations.rename_place_derived ~was ~detail:n.detail n.name], [was]
      its [place_derived] as read, then, changed or not, its marker is deleted
      ([Place_renames.forget] through [Db.write]; an error is only logged).
      {!saved} fires when a commit changed the row; a failed commit is logged,
      marks it tried and stops the run;
    - [Ok Unknown] → nothing written (a rename keeps its old name and its
      marker); when some online source was asked (i.e. [sources] had one on and
      [online]), marked tried and logged [geocode: <id> unknown] (a point no
      source was asked for logs nothing: with every source off that is every
      unnamed point, at every trigger);
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
(** [Busy] while {!downloading} is [Some _] or {!france} {!is_busy} (a « Toute
    la France » run or « Supprimer tout » going). Else {!downloading} is set at
    once, and once the startup load of the packs has ended (it replaces the
    index and {!packs} wholesale), {!Herbier_geo_io.Commune_packs.download}; on
    success, in one step, {!packs} gains the row (usable, replacing one of the
    same code) and {!downloading} returns to [None], the index gains the pack;
    then, when « IGN hors-ligne » is off, [set_place_source t Ign_offline true]
    (which runs {!geocode_pending}), else {!geocode_pending}. An error is logged
    ([communes: download …]). Never raises. *)

val delete_pack :
  t -> Herbier_geo.Communes.Code.t -> (unit, pack_error) result Fut.t
(** [Busy] while that code is downloading or {!france} {!is_busy}. Else
    {!Herbier_geo_io.Commune_packs.delete}; on success the index and {!packs}
    drop it. Names already stored stay (a [place_derived] is a snapshot); the
    switch is not touched. An error is logged ([communes: delete …]). Never
    raises. *)

(** {2 « Toute la France »}

    Every département of the WFS list, one after another, through the very path
    of {!download_pack} (architecture §8). The plan and the run are
    {!Herbier_geo.France_packs}; this is their Brr side. *)

type france =
  | France_idle  (** no run yet, or after {!delete_all_packs} *)
  | France_starting  (** from the tap to the first département's report *)
  | France_running of {
      step : pack_error Herbier_geo.France_packs.step;
      cancelling : bool;  (** a cancel was asked: the run ends after this one *)
    }
  | France_finished of pack_error Herbier_geo.France_packs.outcome
  | France_deleting  (** {!delete_all_packs} going *)

val is_running : france -> bool
(** [France_starting] or [France_running _]: a run is going. *)

val is_busy : france -> bool
(** {!is_running} or [France_deleting]: no other download, delete or run may
    start. *)

val france : t -> france React.signal
(** App-wide (a 4m opened again during a run shows it). A primitive signal;
    starts [France_idle]. *)

val france_plan :
  ?only:Herbier_geo.Communes.Code.t list ->
  t ->
  (Herbier_geo.France_packs.plan, pack_error) result Fut.t
(** [Busy] while {!downloading} is [Some _] or {!france} {!is_busy}; else
    {!departements} (offline → [Offline], no request), then, once the startup
    load of the packs has ended, [France_packs.plan ?only ~downloaded] with
    [downloaded] the codes of the usable {!packs}. One request (the list). *)

val connection : t -> Herbier_bindings.Cap_network.connection Fut.t
(** {!Herbier_bindings.Cap_network.status}'s connection; an error is logged
    ([network: …]) and gives [Unknown]. 4m only warns with it, never blocks. *)

val download_france :
  t ->
  Herbier_geo.France_packs.plan ->
  (pack_error Herbier_geo.France_packs.outcome, pack_error) result Fut.t
(** [Busy] while {!downloading} is [Some _] or {!france} {!is_busy}; [Offline]
    (per {!State.network}) with nothing sent. Else {!france} :=
    [France_starting], the cancel flag cleared, and, once the startup load of
    the packs has ended, the plan computed again over [plan.departements] with
    the usable codes of {!packs} then (a département downloaded since the plan
    was shown is skipped), and [France_packs.Make].run over Fut with:
    - [download d]: offline per {!State.network} → [Error Offline] (nothing
      sent); else what {!download_pack} does after its [Busy] check (so
      {!downloading}, {!packs}, the index, the switch and {!geocode_pending}
      behave as for one département), [Ok row.size_bytes];
    - [classify]: {!france_failure};
    - [sleep ~ms]: a timer, ended early by {!cancel_france};
    - [cancelled]: the cancel flag;
    - [report step]: {!france} := [France_running {step; cancelling}].

    While it goes, the foreground service of
    {!Herbier_bindings.Cap_foreground_run} keeps the process at foreground
    priority (the app in the background, the screen off): started, not awaited,
    once the plan is recomputed when its [todo] is not empty, with the notice «
    IGN hors-ligne : n / total départements »
    ({!Herbier_ui_model.France_text.notification}, [n] the plan's [present]) and
    the action « Interrompre »; updated at each [report] (and by
    {!cancel_france}: the text {!Herbier_ui_model.France_text.cancelling}, no
    action); stopped at the end, before [France_finished]. A refused
    notification permission logs [france: notifications denied]; a service error
    is logged ([france: foreground run …]) and the run goes on in the foreground
    only; in a browser the plugin is absent and nothing is logged.

    At the end {!france} := [France_finished outcome] and one console line
    ([communes: france complete|cancelled|stopped <position>/<total> <bytes>],
    the error's text after a stop). One Géoplateforme request at a time, with
    the {!Herbier_geo_io.Geocoder}'s spacing; no extra pause. Never raises. *)

val france_cause : pack_error -> Herbier_geo.France_packs.cause
(** [Fetch]'s [Network], [Timeout], [Status], [Payload (Not_json _)], other
    [Payload], [Refused] → the cause of the same name ([Bad_payload] for the
    other payload); [Offline], [Busy], [File], [Store] → [Local]. *)

val france_failure : pack_error -> Herbier_geo.France_packs.failure
(** [France_packs.failure_of_cause (france_cause e)]: network, timeout, 429, 5xx
    and a body that is no JSON at all are retried after 5, 20, 60 s, then the
    run stops; 401 and 403 stop it, as do [Refused] and [Local] (the next
    département would fail too); another status or payload skips the département
    (listed at the end). Only this run retries a non-JSON body: elsewhere
    ({!download_pack}, {!geocode_pending}) the user or the next trigger asks
    again. *)

val cancel_france : t -> unit
(** While a run is going: the cancel flag set, {!france}'s [cancelling] set at
    once, a sleeping retry woken. The département being downloaded finishes and
    is kept (a normal pack); the run then ends [Cancelled], or [Complete] if it
    was the last département. Running « Toute la France » again resumes: present
    packs are skipped. A running run's notification shows the cancel at once
    (its text {!Herbier_ui_model.France_text.cancelling}, no action). No-op
    otherwise. *)

val start_france : t -> unit
(** Once, by main, after {!start_uploads}:
    {!Herbier_bindings.Cap_foreground_run.stop} (a service left by an earlier
    page of this process, after a WebView reload, is stopped: no run survives a
    reload), then {!Herbier_bindings.Cap_foreground_run.on_interrupt}: [User]
    (the notification's « Interrompre ») → {!cancel_france}; [Timeout] (Android
    15+ ended the service) → a console error
    [france: foreground service timeout] then {!cancel_france} (the run ends
    [Cancelled] and resumes on the next run). Failures are console errors; in a
    browser the plugin is absent and nothing is logged. Called on dev pages too,
    so a run from the dev hook is interrupted the same way. Never raises. *)

val delete_all_packs : t -> (unit, pack_error) result Fut.t
(** « Supprimer tout »: [Busy] while {!downloading} is [Some _] or {!france}
    {!is_busy}. Else {!france} := [France_deleting] (so nothing else starts
    meanwhile), what {!delete_pack} does after its [Busy] check on every pack of
    {!packs} (unusable ones included), one after another in code order; the
    first error stops and is returned (the ones already deleted stay deleted,
    {!packs} reflects them). The switch is not touched. Then {!france} :=
    [France_idle]. *)

(** {1 Identification}

    Pl@ntNet identification (architecture §12) through the app's one transport
    ({!Plantnet_transport}: the timed fetch, 30 s for an identify POST, no
    retry). The key is the caller's (the Preferences key [plantnet.api_key]):
    nothing is built into the APK, no Supabase call or session is involved (it
    works signed out and while the project is paused). A request stores nothing;
    no console line holds the key or a request's URL, nor a fetch error's text
    (the one line with a JS error's text is a preview read's, the Filesystem
    plugin's message). *)

type image = Identification.image =
  | Preview of Brr.Blob.t  (** a preview in memory (an unsaved shot) *)
  | Stored of Herbier_domain.Ids.Photo_id.t
      (** a stored photo's preview, [previews/<id>.jpg] (4k, 4g), read just
          before the request *)

type channel
(** One per caller (4k, 4g, a dev page): a newer {!identify} on a channel makes
    the older one's answer {!Superseded}. *)

val channel : unit -> channel

type identify_error =
  | Identify_offline  (** {!State.network} offline: nothing sent *)
  | Preview_unreadable of Herbier_domain.Ids.Photo_id.t
      (** that [Stored] photo's preview could not be read (missing on a device
          that has not rebuilt it yet): nothing sent *)
  | Plantnet of Herbier_identify.Plantnet.error

val flora_list_text : identify_error -> string
(** The line a flora list shows when {!floras} fails (4m and 6c): [Plantnet e] →
    {!Herbier_ui_model.Identify_settings.flora_list_error}; [Identify_offline] →
    [flora_list_offline]; [Preview_unreadable _] → [flora_list_generic]. *)

type 'a current =
  | Settled of ('a, identify_error) result
  | Superseded
      (** a newer {!identify} on the same channel was asked since; this answer
          (sent and paid for) is dropped *)

val identify :
  t ->
  channel ->
  key:string ->
  flora:string ->
  ?no_reject:bool ->
  (image * Herbier_identify.Organ.sent) list ->
  Herbier_identify.identified current Fut.t
(** Supersedes every earlier call on [channel], sent or not (the user's latest
    tap wins; the older request is not aborted). Then, in this order:
    - {!Herbier_identify.Plantnet.identify_request}'s refusal (blank key →
      [No_key], no photo → [No_photo]) → [Error (Plantnet e)], nothing sent,
      Make's « not sent » line logged;
    - {!State.network} offline → [Error Identify_offline], nothing sent, the
      line {!Herbier_identify.identify_not_sent} ["offline"]
      ([identify: POST <flora> <n> photo(s) not sent: offline]);
    - the [Stored] previews of the photos sent (the first
      {!Herbier_identify.Organ.max_photos}) read in order; the first that cannot
      be → [Error (Preview_unreadable id)], nothing sent, the read error logged
      with the photo id and the line [… not sent: preview unreadable];
    - else one [Make.identify] request; its line is logged when it settles, even
      when superseded (a credit was spent), and its error is [Plantnet e].

    An answer whose call is no longer the channel's latest resolves
    [Superseded], never a pending future. Never raises, never retries. *)

val floras :
  t ->
  key:string ->
  (Herbier_identify.Plantnet.project list, identify_error) result Fut.t
(** The flora list ([GET /v2/projects]), asked once per session: blank key →
    [Error (Plantnet No_key)], nothing sent, its line logged (even with the list
    cached); the session's list when one was received (no request, no line,
    whatever key is given since: the list is the same for every key); the
    request in flight when there is one (concurrent callers share it); offline →
    [Error Identify_offline], nothing sent, the line
    [identify: GET projects not sent: offline]; else one request, its line
    logged, an [Ok] kept for the session, an error not kept (the next call asks
    again). A caller that joins the request in flight gets its result, errors
    included, whatever its own key: an [Ok] is never a check of the key. Never
    raises. *)

(** {2 4m « Identification »: the key and the two settings}

    The user's Pl@ntNet key lives in Capacitor Preferences
    ({!Herbier_ui_model.Identify_settings.preferences_key}), outside Android's
    backups, never in SQLite, the outbox or Supabase; « Identifier dès la photo
    » and « Flore Pl@ntNet » are local SQLite settings
    ({!Herbier_store.Settings.Identify_on_photo},
    {!Herbier_store.Settings.Plantnet_project}). No console line holds the key
    or its mask. *)

val load_plantnet_key : t -> unit Fut.t
(** Once, by main, right after the app is built. Reads the Preferences key
    (through the key's write queue, so after any write started before):
    [Ok stored] → {!Herbier_ui_model.Identify_settings.key_of_stored}; [Error e]
    → [Absent] and the console error
    [identify: key unreadable: <Cap_error.to_string e>]. Never raises. *)

val plantnet_key : t -> Herbier_ui_model.Identify_settings.key React.signal
(** [Loading] until {!load_plantnet_key} reads it. *)

val set_plantnet_key :
  t -> string -> (unit, Herbier_bindings.Cap_error.t) result Fut.t
(** 4m « Modifier » → « Enregistrer ». [Identify_settings.Key.of_input input]:
    - [None] (blank) → [Cap_preferences.remove]; on [Ok] the signal becomes
      [Absent] and the console logs [identify: key cleared];
    - [Some k] → [Cap_preferences.set] of the trimmed key; on [Ok] the signal
      becomes [Present k], log [identify: key saved].

    On [Error e]: the signal is unchanged (it never shows a key that is not
    stored), log [identify: key not saved: <Cap_error.to_string e>], [Error e]
    returned. Reads and writes of the key run one after another, in call order.
    Never raises. *)

val identify_on_photo : t -> bool React.signal
(** 4m « Identifier dès la photo », from [create]'s [identification]. *)

val set_identify_on_photo :
  t -> bool -> (unit, Herbier_store_io.Db.error) result Fut.t
(** Sets the signal at once (a second tap while the write runs flips it back),
    then [Db.write (Settings.set Identify_on_photo v)]. Error → logged
    ([réglages: identification on_photo …]), the signal goes back to the value
    last confirmed in SQLite (the startup value or the last successful write)
    when no later call was made, [Error e]. *)

val plantnet_flora : t -> Herbier_store.Settings.flora option React.signal
(** The stored flora; [None] = « Automatique » ([all]). *)

val set_plantnet_flora :
  t ->
  Herbier_store.Settings.flora option ->
  (unit, Herbier_store_io.Db.error) result Fut.t
(** Signal at once, then [Settings.set Plantnet_project f] ([Some f]) or
    [Settings.unset Plantnet_project] ([None]: no row is kept for « Automatique
    »). Error → as {!set_identify_on_photo} ([… flora …]). *)

val identify_gate : t -> Herbier_ui_model.Identify_settings.gate React.signal
(** [Identify_settings.gate] of {!plantnet_key} and {!State.network}'s [online],
    kept updating for the app's lifetime: what the Identifier buttons bind their
    disabled state and reason to, and what [Ready k] gives them the key from. *)

val resolve_choice :
  Herbier_identify.Plantnet.proposal ->
  Herbier_ui_model.Identify.Choice.resolution Fut.t
(** The GBIF taxon of a proposal chosen in the identification layer:
    [Herbier_refs_io.Http.run] of {!Herbier_ui_model.Identify.Choice.resolve}
    (the reference sources' queue and timeout). Never fails, never raises. Logs:
    [Unavailable m] → [identify: GBIF unavailable for <what>: <m>] (as an
    error); [Unknown] → [identify: GBIF has no species for <what>]; [<what>] is
    ["gbif <k>"] or the Latin name with its author (no Pl@ntNet key or URL: GBIF
    needs none). Nothing is written. *)
