(** The originals' upload queue on the device (architecture §5): keeps each
    Drive-bound original under [originals/<photo id>] with a row in [uploads],
    starts its Drive resumable session (one at a time), hands the bytes to a
    WorkManager job ({!Herbier_bindings.Cap_uploader}) and records the outcome
    in the photo row. The decisions are {!Herbier_photos.Upload_queue.next}'s.
    The token comes from the caller ([Auth.drive_token], its error as a string;
    herbier_sync is not a dependency). *)

module Photo := Herbier_domain.Photo
module Db := Herbier_store_io.Db

type t

val create :
  db:Db.t ->
  commit:(Herbier_store.Outbox.edit list -> (int, Db.error) result Fut.t) ->
  token:(interactive:bool -> (string, string) result Fut.t) ->
  drop_token:(string -> unit Fut.t) ->
  wifi_only:(unit -> bool) ->
  t
(** No IO. [commit] writes synced rows (the app's commit: the edits' outbox
    entries, then its [saved] and the engine's local write). [wifi_only] is read
    at each enqueue. *)

type keep_error =
  | Write of Herbier_bindings.Cap_error.t
      (** the file was not written (a partial one deleted again); no row *)
  | Store of Db.error  (** the row was not written; the file deleted again *)

val keep_error_to_string : keep_error -> string

type kept = Kept | Not_drive  (** [original_target] is [App_only] *)

val keep : t -> Photo.t -> Brr.Blob.t -> (kept, keep_error) result Fut.t
(** For a photo whose [original_target] is [Drive] (else [Ok Not_drive], nothing
    done): writes the original's bytes at [Files.original photo.id], then
    [Uploads.put {photo_id; path; mime; size_bytes; attempts = 0; session =
     None; last_error = None; created_at = now}] ([mime] the blob's type,
    ["application/octet-stream"] when empty; [size_bytes] its byte length) →
    [Ok Kept]. Starts nothing (see {!run}). An error leaves this install's photo
    without its original: [commit]s
    [Photos.set_upload ~state:Failed ~drive_file_id:None] at once (its own
    failure a console line), then the error. A process killed between the file
    and the row leaves a file no row points to: accepted, as for the commune
    packs (architecture §3). *)

val run : t -> interactive:bool -> unit Fut.t
(** One pass over the [uploads] rows, oldest first. Single-flight: a call while
    a pass runs makes that pass run once more when it ends (once, however many
    calls; interactive when any of them was) and resolves with it. The pass:
    - [Cap_uploader.jobs ()]; an error (no plugin in a browser, …) is one
      console line and ends the pass (rows untouched);
    - [Uploads.all]; for each row, [Photos.get] (an error: console line, next
      row), then {!Herbier_photos.Upload_queue.next}, then:
    - [Nothing]: nothing;
    - [Discard]: [Cap_uploader.cancel] (error logged), [Uploads.remove],
      [Files.delete] (a missing file is not an error);
    - [Discard_uploaded f]: [Drive_trash.add] for [f.id], then as [Discard] (a
      failed add: console line, nothing else, the next pass again);
    - [Finish f]: commits
      [Photos.set_upload ~state:Uploaded ~drive_file_id:(Some f.id)]; once
      committed, [Settings.set Last_upload_at now] (its error a console line),
      [Uploads.remove] and [Files.delete]; a failed commit leaves all as is (the
      next pass: the same action, or, the job pruned, [Enqueue s] while the
      row's session is usable — the job's status query finds the upload complete
      — else [Start] → the lookup → [Already_there]);
    - [Give_up]: row updated ([attempts], [last_error]), then commits
      [Photos.set_upload ~state:Failed ~drive_file_id:None]; file kept;
    - [Retry]: row updated ([last_error], the session dropped for [Restart]),
      then as [Enqueue s] ([Resume s]) or [Start] ([Restart]); its [attempts]
      are saved once the new job is enqueued (the failed one, still listed until
      then, is counted again by each pass from the same saved value);
    - [Enqueue s]:
      [Cap_uploader.enqueue ~network:(if wifi_only () then Unmetered else Any)];
      a ["FILE_NOT_FOUND"] rejection is a [Give_up] of
      {!Herbier_photos.Upload_queue.missing_file}; ["INVALID_ARGUMENT"] (the
      same each time) one counted attempt, the session dropped; any other (the
      plugin, WorkManager) the row's [last_error] only;
    - [Start] (skipped once a token or an [Account] error happened in this
      pass): reads the observation and its plant (folder
      [Drive.species_folder]), names the file [Drive.file_name] at the device's
      offset at [taken_at], runs [Photos_io.Drive.start_session] through
      {!Drive_root.run} (the stored root folder read before, what the start
      learnt about it written before acting on its outcome); the root folder
      setting read fails (a {!Drive_root.stored} [Error]) → console error, no
      Drive request, next row; [Already_there f] → as [Finish f]; [Session url]
      → row's [session], then enqueued; [Token e] → console line, no row change,
      no more [Start] this pass; [Drive e] → {!Herbier_photos.Drive.error_scope}
      [Account]: the row's [last_error] only, no more [Start]; [This_file]:
      {!Herbier_photos.Upload_queue.count_failure} from the saved row, the
      session dropped (the row only: the next pass starts again, not this one,
      so a lasting error does not use every attempt at once).

    Then the Drive bin: [Drive_trash.all], oldest first, each row by
    {!Herbier_photos.Upload_queue.trash_next} ([Photos.get]: live or not):
    [Forget_trash] → [Drive_trash.remove]; [Trash_failed] → nothing; [Trash]
    (skipped once the gate is closed, by the uploads above or a row before) →
    {!Drive.trash_original} with the same token, then by
    {!Herbier_photos.Upload_queue.trash_outcome}: [Trashed] → the row removed;
    [Blocked e] → the row's [last_error], no more trash this pass; [Counted] →
    the row's [attempts] and [last_error]; a [Token e] → console line, row
    untouched, no more trash this pass. The bin part runs even when
    [Cap_uploader.jobs] or [Uploads.all] failed (it needs neither).

    Starts run one after the other and passes never overlap, so sessions are
    started one at a time (architecture §5). Every action but [Nothing] logs a
    console line « upload: <photo id> <action> », and a [Start] also logs its
    outcome (never a token or a session URL). Always resolves, as long as the
    pass's continuations do not raise (they return results). *)

val exclusive : t -> on_raise:(string -> 'a) -> (unit -> 'a Fut.t) -> 'a Fut.t
(** Runs [f] when no pass is running (it waits for the current one, and the
    passes asked for during it, to end); a pass asked for while [f] runs starts
    after [f] resolves (single-flight rule unchanged), and resolves then. For
    writes to the root folder settings that must not interleave with a pass's
    {!Drive_root.run} (which reads the root before and writes its change after).
    [f] must not wait for {!run} or {!exclusive} (each would wait for [f]). An
    exception raised starting [f] (as {!run}'s pass: [Failure],
    [Invalid_argument], [Not_found], a JS error) is a console error « upload:
    exclusive: … » and the result is [on_raise] of its text; the passes go on. A
    raise in a later continuation of [f] is not caught. *)

val wifi_changed : t -> unit Fut.t
(** After « Envoyer seulement en Wi-Fi » changed: {!run} [~interactive:false],
    whose next pass (this one, or the one after a pass already running) first
    enqueues again, with the new network (REPLACE), every waiting job whose row
    has a usable session ({!Herbier_photos.Upload_queue.on_network_change}) and
    whose action is otherwise [Nothing]. A running job finishes on its network.
    Within {!run}: never alongside a pass. *)

val send_now : t -> unit Fut.t
(** 4m « Envoyer maintenant »: asks for an interactive {!run} whose pass (this
    one, or the one after a pass already running) first resets every row whose
    photo is {!Herbier_photos.Upload_queue.retryable}: [Cap_uploader.cancel] of
    its job (error logged), the row written with
    [attempts = 0; last_error = None] (its session kept: a usable one is
    enqueued again, else a new one is started), then all those photos back to
    [Pending] in one [commit] of
    [Photos.set_upload ~state:Pending ~drive_file_id:None]; a commit error is a
    console line and leaves them [Failed] (the rows' reset stays). The reset
    rows' old jobs are ignored from then on until a new job is enqueued for the
    row, or the row is finished, discarded or given up (WorkManager keeps
    listing a finished job as failed after a cancel: it is not counted again,
    even by a later pass when this one could not start a new job). Then the pass
    as usual (rows that were only waiting are started or enqueued as {!run}
    does). The trash rows that gave up
    ({!Herbier_photos.Upload_queue.trash_gave_up}) are written back with
    [attempts = 0; last_error = None] before it. Resolves with that pass. Never
    alongside a pass. *)

val stop_drive : t -> (unit, Db.error) result Fut.t
(** 4m storage radio → « Dans Herbier seulement » with « Ne pas les envoyer »:
    asks for a silent {!run} whose pass first commits, in one [commit],
    [Photos.set_app_only id ~at:now] for every row whose photo is
    [Photo.awaiting_drive]; the pass then [Discard]s them (job cancelled, row
    and [originals/<id>] deleted: their originals are gone, only the previews
    remain). Resolves, once that pass is over, with that commit's outcome: a
    read or commit error (also a console line) leaves every photo as it was, and
    they upload as before; [Error (Raised _)] when the pass raised before it. *)

type entry = {
  row : Herbier_store.Uploads.t;
  photo : Photo.Upload_state.t option;  (** [None]: photo absent or deleted *)
  job : Herbier_bindings.Cap_uploader.job option;
}

val entries : t -> (entry list, Db.error) result Fut.t
(** For #dev/uploader: the rows, their photos' states and their jobs (none when
    the plugin is missing). *)

val trash_entries :
  t -> (Herbier_store.Drive_trash.t list, Db.error) result Fut.t
(** The [drive_trash] rows (4m « File d'envoi », #dev/uploader). *)
