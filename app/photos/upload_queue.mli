(** The originals' upload queue (architecture §5), its decisions without IO: for
    one queued original — its photo row, what the device remembers of it
    ({!pending}) and its upload job, if any — what the queue does next. Run by
    [Herbier_photos_io.Upload_queue]. *)

module Photo := Herbier_domain.Photo

val max_attempts : int
(** 3: failed attempts (each a {!count_failure}) before the photo goes [Failed].
*)

val session_lifetime : Ptime.Span.t
(** 6 days: Drive keeps a resumable session one week; one day of margin. *)

type session = {url : string; created_at : Ptime.t}

val equal_session : session -> session -> bool

val session_usable : now:Ptime.t -> session -> bool
(** [created_at <= now] and [now - created_at < session_lifetime]. A
    [created_at] after [now] (the clock went back) is not usable. *)

type pending = {attempts : int; session : session option}

(** How a job ended without uploading. *)
type failure =
  | Answered of {status : int; body : string}
      (** the session's final answer, any status the job does not retry: 404/410
          (session gone), another 4xx, … *)
  | File_missing  (** the job found no file to send *)
  | Gave_up of string  (** transient failures on every run; the last one *)

type job =
  | Waiting  (** enqueued or blocked *)
  | Running
  | Succeeded of {status : int; body : string}
  | Failed of failure
  | Cancelled

type resume = Resume of session | Restart

type action =
  | Nothing
  | Start  (** start a session (needs a token), then enqueue it *)
  | Enqueue of session  (** a usable session and no live job *)
  | Finish of Drive.file  (** uploaded: the photo row, then cleanup *)
  | Retry of {attempts : int; error : string; resume : resume}
  | Give_up of {attempts : int; error : string}
  | Discard  (** nothing to upload any more: cancel, delete row and file *)

val equal_action : action -> action -> bool

val pp_action : Format.formatter -> action -> unit
(** One line, never the session's URL (a credential): ["enqueue"],
    ["retry 2 (HTTP 503) resume"], ["finish <file id>"], … *)

val next :
  now:Ptime.t -> photo:Photo.t option -> pending -> job option -> action
(** [photo]: the live photo row, [None] when absent or soft-deleted. First rule
    that applies:
    + [photo = None], [original_target <> Drive], or [upload_state] is
      [Uploaded] or [Original_missing] → [Discard].
    + [upload_state = Failed] → [Nothing] (waits for « Envoyer maintenant »).
    + ([Pending]) by [job]:

    - [Some Waiting | Some Running] → [Nothing];
    - [Some (Succeeded {status = 200 | 201; body})]: {!Drive.decode_file} [Ok f]
      → [Finish f]; [Error _] → [Start] (the lookup by [appProperties] finds the
      file);
    - [Some (Succeeded _)] with another status → [Start];
    - [Some (Failed (Answered {status = 404 | 410; _}))]: the session is gone;
      [fail] with [resume = Restart] whatever the session's age (a session that
      answers 404 at once would otherwise start a new one on every pass);
    - [Some (Failed File_missing)] → [Give_up] of {!missing_file};
    - [Some (Failed (Answered {status; body}))] →
      [fail (Drive.error_to_string (Drive.error_of_answer ~status ~body))];
    - [Some (Failed (Gave_up m))] → [fail m];
    - [Some Cancelled | None] → [Enqueue s] when [session = Some s] and
      {!session_usable} [~now s], else [Start].

    where [fail e] is {!count_failure}: [Give_up_now] → [Give_up], else
    [Retry {…; resume}] with [resume = Resume s] for a usable session [s], else
    [Restart].

    A failed job stays listed until a new job replaces it, so the caller saves a
    [Retry]'s [attempts] only once the new job is enqueued: until then each pass
    counts that failure again from the same saved value. *)

type count = {attempts : int; error : string}

val missing_file : pending -> count
(** [{attempts = attempts + 1; error = "original file missing"}]: a missing
    original is final, whatever {!max_attempts} (the job's [File_missing] and an
    enqueue rejected with ["FILE_NOT_FOUND"] alike). *)

(** One more failed attempt for this photo. *)
type counted =
  | Retry_later of count  (** the next pass tries again *)
  | Give_up_now of count  (** [attempts >= max_attempts] *)

val count_failure : pending -> string -> counted
(** [attempts + 1] with this error. *)

val on_network_change : now:Ptime.t -> pending -> job option -> session option
(** After « Envoyer seulement en Wi-Fi » changed: [Some s] when the job is
    [Waiting] and [s] the pending's usable session (the job is enqueued again
    under the new constraint); [None] otherwise (a running job finishes on its
    network, a finished one is the pass's to handle). *)

(** Whose problem a failed session start is. *)
type scope =
  | Account  (** the same for every photo: stop starting sessions this pass *)
  | This_photo  (** counts as one of this photo's attempts *)

val equal_scope : scope -> scope -> bool

val start_error_scope : Drive.error -> scope
(** [Unauthorized], [Api_disabled], [Scope_missing], [Quota_full],
    [Rate_limited], [Server _], [Network _] → [Account]; [Not_found], [Http _],
    [Malformed _] → [This_photo], which the caller counts with {!count_failure}
    ({!Drive.error_to_string}) and the session dropped. *)
