(** The app's side of the keep-alive job (architecture §4, keep-alive): the
    job's own session ({!Auth.on_job_session}'s second grant), and the pending
    outbox entries handed to it as rendered requests ({!Wire}).

    The engine hands the queue off at the end of each push ({!hand_off}) and
    takes it back before the next one ({!before_push}), the first push of every
    process included; why, and why the app does not hand it off on going to the
    background: architecture §4 (keep-alive, the queue).

    Every dispatch but {!report}'s and {!run_now}'s runs after the previous one
    has resolved, so a hand-off whose outbox read is still running cannot land
    after a later take-back. That order holds among the app's dispatches only: a
    WorkManager run is another engine on another thread, which the job script
    guards against itself. A dispatch that has not answered within 15 s fails
    with [Timed_out]; {!run_now} has no timeout. While a dispatch runs, the
    plugin holds Capacitor's one plugin thread: every other native plugin call
    (SQLite, Preferences) waits for it. Failures are logged to the console
    (["keepalive: …"], never a token); apart from {!before_push}'s, they change
    nothing for the app: the keep-alive is best effort. A build without the
    plugin (the browser) has no job: the first [Unavailable] dispatch turns
    every later one into a no-op. *)

module Wire = Wire
(** The job's contract: its events, the requests and documents it is handed, its
    small answers. *)

module Report = Report
(** What the job reports. *)

type t

val create : db:Herbier_store.Db.t -> t
(** No IO, no listener. *)

type error =
  | No_runner  (** no plugin in this build *)
  | Rejected of string
      (** the plugin or the job refused the dispatch: what it would have written
          was not *)
  | Timed_out of string  (** the event: no answer within 15 s *)
  | Bad_answer of string  (** an answer that does not decode, or says no *)

val error_to_string : error -> string
(** One line, never a token. *)

val before_push : t -> (unit, error) result Fut.t
(** For {!Engine}: when the job may hold a queue (a hand-off since the last
    confirmed take-back, or none yet in this process), {!reclaim}; else [Ok ()]
    at once (no dispatch). [Error] when that take-back is not confirmed: it
    failed for another reason than a missing plugin, or a request of the job's
    queue was still in flight after the job waited for it. The next call tries
    again. *)

val hand_off : t -> unit Fut.t
(** For {!Engine} after each push, and #dev/keepalive: reads
    [Outbox.next ~limit:Wire.queue_limit] and, when it is not empty, dispatches
    [handOff] with {!Wire.queue_doc}; skipped entries and failures are logged. A
    [Rejected] hand-off left the job without that queue: no take-back is needed
    for it, but one an earlier hand-off may have left still is. Resolves once
    done; never fails. *)

val reclaim : t -> (unit, error) result Fut.t
(** Dispatches [reclaim]: the job forgets its queue, and answers once no request
    of it is in flight (it waits 10 s at most: [Error (Bad_answer _)] when one
    still is). Does not touch the outbox: entries the job pushed are pushed
    again by the engine (idempotent upserts, in [seq] order). A missing plugin →
    [Ok ()]. *)

val replace_session : t -> Auth.Session.t -> (unit, error) result Fut.t
(** For a new grant: [takeSession] then [setSession] with {!Wire.session_doc} on
    {!Backend}'s URL and key, both in one step of the dispatch chain; then the
    taken session is logged out (as {!drop_session} does). When the take or the
    set fails, or there is no job, the new session is logged out instead of
    being left live with nobody holding it ([Error]); a failed take leaves the
    job its old session. *)

val set_session : t -> Auth.Session.t -> (unit, error) result Fut.t
(** #dev/keepalive: [setSession] alone. Replaces whatever session the job had
    (and drops its queue), without logging either out. *)

val drop_session : t -> (unit, error) result Fut.t
(** [takeSession] (the job forgets its session and its queue), then, when one
    came back, best-effort server-side logout of it: refreshed first when its
    access token is {!Auth.Session.expired} (a refresh answered with
    {!Auth.Gotrue.revokes_session} means it is already dead: done), then
    {!Auth.Gotrue.logout}; failures logged, [Ok ()]. [Error] when the dispatch
    or its answer failed. A take that timed out is still followed: the session
    it returns late is logged out then. A [Rejected] take leaves the job its
    session, until the next sign-in replaces it. *)

val report : t -> (Report.t, error) result Fut.t
(** [report], decoded. *)

val run_now : t -> (Report.t, error) result Fut.t
(** #dev/keepalive: dispatches [runNow] (one run in a runner context while the
    app is open: the queue is skipped), then {!report}. *)
