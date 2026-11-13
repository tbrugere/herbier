(** The account's lifecycle as a state machine, sans IO: the phase (and so the
    status), the foreground flag, the sign-in attempt, the session's generation
    and the failed refreshes in a row. Each transition returns the next state
    and its effects, in the order [Herbier_sync]'s Auth runs them; Auth keeps
    the futures (Preferences, GoTrue, the plugin), the timer and the hooks. *)

type status =
  | Unconfigured  (** this build has no Supabase URL/key or Google client id *)
  | Restoring  (** before Preferences have been read *)
  | Signed_out
  | Signed_in of {email : string option}
[@@deriving eq]

type t

type action =
  | Notify of status  (** the status changed: call [on_change] with it *)
  | Reschedule
      (** stop the timer; with a session and in the foreground, arm it for the
          session's {!Session.refresh_in}, read when this action runs *)
  | Retry_in of Ptime.Span.t
      (** stop the timer; with a session and in the foreground, arm it for this
          span *)
  | Stop_timer
  | Start_refresh  (** the (single-flight) refresh, not awaited *)
  | Log of string
  | Warn of string
  | Console_error of string
  | Logout_server of Session.t  (** best effort, not awaited *)
  | Job_dropped  (** the keep-alive job's session hook, with [Dropped] *)
  | Forget_stored of {generation : int}
      (** after the Preferences writes queued so far, remove the stored session
          unless the generation has moved on meanwhile *)
[@@deriving eq]

val create : configured:bool -> t
(** [Restoring], or [Unconfigured] for good when not [configured]; in the
    foreground. *)

val status : t -> status
val configured : t -> bool
val session : t -> Session.t option
val foreground : t -> bool

val armed : t -> bool
(** In the foreground with a session: the refresh timer may run. *)

val generation : t -> int

val stale : t -> generation:int -> bool
(** A sign-in, a sign-out or a revoked refresh has replaced the session since
    [generation] was read. *)

val current : t -> attempt:int -> bool
(** [attempt] is still the latest sign-in. *)

val expiry_line : Session.t -> string
(** ["expires <RFC 3339, UTC>"], the log lines' tail. *)

(** {1 Transitions} *)

val restored :
  t -> generation:int -> (string option, string) result -> t * action list
(** The stored session as read when [generation] was current ([Error]: why the
    read failed). Stale: nothing. Read failure → [Console_error], [Signed_out];
    absent → [Signed_out]; parsed → [Signed_in], [Log]; unparseable → [Warn],
    [Signed_out], [Forget_stored]. *)

val resumed : now:Ptime.t -> t -> t * action list
(** Back in the foreground: a session that is {!Session.due} is refreshed, any
    other is rescheduled. *)

val paused : t -> t * action list
(** In the background: the timer stopped, logged. *)

val refreshed : t -> Session.t -> not_stored:string option -> t * action list
(** A current refresh's session, once its Preferences write has resolved
    ([not_stored]: why it failed, logged as an error): kept, the failure count
    reset, logged and rescheduled. *)

val revoked : t -> Gotrue.error -> t * action list
(** A current refresh that GoTrue refused for good: the session dropped (a new
    generation), logged, and the job's session too. *)

val refresh_failed : t -> why:string -> t * action list
(** A current refresh that failed transiently: logged, retried after
    {!Backoff.delay} of the failures in a row. *)

val sign_in_started : t -> t * int
(** A new sign-in attempt, the latest; its number. *)

val kept : t -> Session.t -> t * action list
(** The latest sign-in's session, once stored: it replaces the session (a new
    generation), logged, and the previous one is logged out server-side. *)

val signed_out : t -> t * action list
(** The stored session removed: the session dropped (a new generation), logged,
    and the job's session too. *)

val expiry_moved : now:Ptime.t -> t -> t * action list
(** « Expirer »: the session's expiry moved to [now + refresh_margin + 30 s],
    logged and rescheduled. Without a session: nothing. *)
