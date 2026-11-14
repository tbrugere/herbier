(** Binding to Herbier's own [Uploader] Capacitor plugin
    (android/app/src/main/java/re/bruge/herbier/UploaderPlugin.java and
    UploadWorker.java, [globalThis.herbier.uploader], native only): one
    WorkManager job per file, which PUTs the file's bytes to a Drive resumable
    session URL (resuming after an interruption) under a network constraint, and
    keeps the final answer for the app to read. Jobs outlive the app's process:
    an app swiped away keeps them; a force-stop pauses them until the app next
    starts; an uninstall removes them. *)

type network =
  | Any  (** WorkManager [NetworkType.CONNECTED] *)
  | Unmetered  (** [NetworkType.UNMETERED]: « Envoyer seulement en Wi-Fi » *)

type failure =
  | Answered of {status : int; body : string}
      (** the session's last answer, a final one: any status the job does not
          retry (not 200/201, 308, 408, 429 or 5xx), e.g. 404/410 (session
          unknown or expired) or another 4xx; [body] at most 3 000 chars *)
  | File_missing  (** no readable file at the job's path *)
  | Gave_up of string
      (** transient failures (IO error, 408, 429, 5xx, an incomplete 308) on
          each of the job's 10 runs, the last one's message (an exception's
          class name, never its text); or at once on bad input (["bad input"])
          or an unexpected exception (its class name); or a job that failed
          without saying why (empty output: a Throwable the worker does not
          catch, or an unknown [error]): [""] *)

type state =
  | Enqueued  (** waiting to run (constraint met or not, backoff) *)
  | Blocked
  | Running
  | Succeeded of {status : int; body : string}
      (** 200 or 201 from the session: [body] is Drive's file JSON
          ([fields=id,webViewLink] of the session), at most 3 000 chars *)
  | Failed of failure
  | Cancelled

type job = {id : string; state : state; attempts : int}
(** [id] as given to {!enqueue}; [attempts] = WorkManager's [runAttemptCount].
*)

val equal_job : job -> job -> bool

val enqueue :
  id:string ->
  path:string ->
  url:string ->
  mime:string ->
  network:network ->
  (unit, Cap_error.t) result Fut.t
(** [enqueue({id, path, url, mimeType, network: "connected" | "unmetered"})]:
    unique work ["original-<id>"], policy REPLACE (a job of that id, running or
    not, is cancelled and replaced: the new one resumes the session where the
    old one stopped, since every run first asks the session what it holds),
    exponential backoff from 30 s. [path] is relative to the app's files
    directory ([Directory.Data], as {!Cap_filesystem}); [url] is sent as is and
    never logged (it is a credential). Rejections: ["INVALID_ARGUMENT"] ([id]
    empty or not of [A-Za-z0-9-]; [path] empty, absolute or resolving outside
    the files directory; [url] outside the allow-list:
    ["https://www.googleapis.com/upload/drive/v3/files?"], plus plain [http] to
    host [localhost] or [127.0.0.1] without user info in debug builds only;
    [mimeType] empty), ["FILE_NOT_FOUND"] (no file at [path]). Plugin missing →
    [Unavailable "uploader"]. Never raises. *)

val jobs : unit -> (job list, Cap_error.t) result Fut.t
(** [jobs()] →
    [{jobs: [{id, state, attempts, httpStatus?, body?, error?, message?}]}]:
    every job the plugin enqueued that WorkManager still remembers (finished
    ones are pruned after a day or more), one per [id] (the current one of its
    unique work; a replaced one is not listed). Wire [state]
    ["ENQUEUED" | "BLOCKED" | "RUNNING" | "SUCCEEDED" | "FAILED" | "CANCELLED"];
    ["SUCCEEDED"] needs integer [httpStatus] and string [body]; ["FAILED"] is
    [Answered] with [httpStatus] (and [body], [""] when absent), else
    [File_missing] for [error = "FILE_NOT_FOUND"], else [Gave_up message] for
    [error = "GAVE_UP"] ([""] without a message), else (no [error], or an
    unknown one: the job failed with empty output) [Gave_up ""]. Anything else
    (no [jobs] array, an entry without a string [id] or integer [attempts], an
    unknown [state], a SUCCEEDED entry missing what it needs, a field of the
    wrong type) → [Error (Unexpected "<field>")] naming the field (["jobs"],
    ["id"], ["attempts"], ["state"], ["httpStatus"], ["body"], ["error"],
    ["message"]); no partial list. *)

val cancel : id:string -> (unit, Cap_error.t) result Fut.t
(** [cancel({id})]: cancels the unique work ["original-<id>"]; no such job is
    [Ok ()]. ["INVALID_ARGUMENT"] as {!enqueue}'s [id]. *)

type listener
(** A registered listener (a [PluginListenerHandle]). *)

val on_change : (unit -> unit) -> (listener, Cap_error.t) result Fut.t
(** Registers [f] for the plugin's ["jobsChanged"] event, sent while the app
    runs whenever a job of the plugin changes state (WorkManager's LiveData by
    tag). [f] is called from the JS event, outside any React update step. *)

val remove : listener -> (unit, Cap_error.t) result Fut.t
(** [handle.remove()]. *)
