(** The account (architecture §4, "Auth on device"): Google sign-in through
    Credential Manager, its id token exchanged for a Supabase session (the
    id-token grant, over fetch: {!Gotrue}), the session kept in Capacitor
    Preferences and refreshed before expiry by a timer that runs while the app
    is in the foreground (from {!start} on; cleared on background, the refresh
    done at once on resume when due). *)

module Session = Session
(** The stored session and its refresh timing. *)

module Gotrue = Gotrue
(** GoTrue's requests and answers, sans IO. *)

module Nonce = Nonce
(** Hex encoding of the sign-in nonce. *)

module Server = Server
(** The GoTrue calls, shared with the keep-alive job's session. *)

type status =
  | Unconfigured  (** this build has no Supabase URL/key or Google client id *)
  | Restoring  (** before {!start} has read Preferences *)
  | Signed_out
  | Signed_in of {email : string option}

val equal_status : status -> status -> bool

type error =
  | Not_configured  (** {!sign_in} in an [Unconfigured] build *)
  | Replaced
      (** a later {!sign_in} call took over: this one's result is dropped *)
  | Cancelled  (** the user dismissed the Google chooser *)
  | Google of Herbier_bindings.Cap_error.t
      (** any other plugin failure: no Google account, Play services missing, a
          misconfigured client (Credential Manager's DEVELOPER_ERROR / "No
          credentials available") *)
  | Not_allowed
      (** {!Gotrue.signup_disabled}: no Herbier user for this account *)
  | Network of string  (** fetch failed or timed out (15 s) *)
  | Server of Gotrue.error  (** any other GoTrue answer *)
  | Storage of Herbier_bindings.Cap_error.t
      (** Preferences failed: the new session was not kept *)
  | Crypto of string  (** WebCrypto's random bytes or digest failed *)
  | No_session  (** {!access_token} or a refresh without a session *)

val error_to_string : error -> string
(** One line for logs and the dev page; never a token. *)

type t

val create : unit -> t
(** Reads {!Backend}: [Unconfigured] when any of its three values is [""], else
    [Restoring]. No IO, no listener: a value made for a dev page that is never
    started stays there. *)

val start : t -> on_change:(status -> unit) -> unit
(** Once per process (main, through [App.start_auth]); a second call is ignored.
    Unless [Unconfigured]: reads the Preferences key ["auth.session"] →
    [Signed_out] (absent), [Signed_in] (parsed; a stored-but-unparseable value
    is removed, console warning) or [Signed_out] with a console error
    (Preferences failed, key kept); registers [Cap_app.on_state_change]
    (registration failure: console warning, timers still run); then auto-refresh
    as on a resume. A sign-in that succeeded before the read resolved wins over
    what was stored. [on_change] is called with every new status, from future or
    listener callbacks (never inside a React update step, never synchronously
    from [start]), and not called when the status does not change. *)

val status : t -> status

val sign_in : t -> (unit, error) result Fut.t
(** Unconfigured → [Error Not_configured]. Otherwise: initialise the plugin
    (once per process, again after a failed initialisation), Google sign-in with
    a fresh nonce (architecture §4), the id-token grant, write the session to
    Preferences; only then replace the in-memory session, emit [Signed_in],
    reschedule the refresh, and log out the previous session server-side if
    there was one (best effort, not awaited, errors to the console). A call made
    while an earlier one is still running takes over: the earlier one ends with
    [Error Replaced], its session (if it made one) logged out server-side and
    not kept. Failures leave the previous status and session untouched: cancel →
    [Cancelled]; other plugin error → [Google e]; fetch failure → [Network];
    [signup_disabled] → [Not_allowed]; other GoTrue error → [Server];
    Preferences write → [Storage] (the new session logged out server-side). A
    sign-in that ends [Ok ()] also grants the keep-alive job a session of its
    own ({!on_job_session}). Never raises. *)

type job_session = Granted of Session.t | Dropped

val on_job_session : t -> (job_session -> unit) -> unit
(** Sets the one hook for the keep-alive job's session (a later call replaces
    it; until the first, a granted session is logged out at once). Called from
    future callbacks, never synchronously from the call that triggers it:
    - {!sign_in}: once it has ended [Ok ()] (the app's session stored,
      [Signed_in] emitted), a second [Gotrue.id_token_grant] with the same id
      token and raw nonce (GoTrue keeps no record of used ones): its session →
      [Granted s]; its failure → logged (["auth: job session …"]) and [Dropped],
      [sign_in]'s result unchanged (the app is signed in, the job has no session
      until the next sign-in). When another {!sign_in}, a {!sign_out} or a
      revoked refresh has happened meanwhile, the second session is logged out
      and nothing is called. A sign-in that does not end [Ok ()] calls nothing.
    - {!sign_out} that reaches [Signed_out], and a refresh that drops a revoked
      session → [Dropped].
    - {!debug_import} → nothing (#dev/keepalive imports the job's own session).
*)

val sign_out : t -> (unit, error) result Fut.t
(** Signed in: POST {!Gotrue.logout} (its failure is logged, not returned),
    [Cap_social_login.logout_google] (same), remove the Preferences key
    ([Error (Storage _)] if that fails, status unchanged), stop the timer, emit
    [Signed_out]. Signed out already: [Ok ()]. Writes of the key run one after
    the other: a refresh in flight that resolves later changes neither memory
    nor Preferences, and one that resolved before is stored before the key is
    removed. A sign-in that completes meanwhile wins: [Ok ()], the new session
    kept. *)

val access_token : t -> (string, error) result Fut.t
(** For the PostgREST transport: awaited per request, its token handed to a
    per-request connection
    ([Postgrest.Client.supabase_conn ~token:(fun () -> Some token)]). No session
    (also while [Restoring]) → [Error No_session]. Session not {!Session.due} →
    its token. Due → the (single-flight) refresh: [Ok] → the new token; refresh
    failed transiently and the token not {!Session.expired} → the old token;
    else that refresh's error ([Network _] / [Server _]; a revoked session →
    [Error No_session] after the status went to [Signed_out]). *)

val refresh_now : t -> (unit, error) result Fut.t
(** The refresh, now, whatever {!Session.due} says. Same rules as the timer's:
    success stored and rescheduled, a revoked session dropped, a transient
    failure retried later. {!Engine} calls it after a 401; #dev/auth's button
    too. *)

(** {1 Dev page only} *)

val session_expires_at : t -> Ptime.t option

val debug_expire : t -> unit
(** « Expirer »: sets the in-memory session's [expires_at] so that it becomes
    {!Session.due} in 30 s (Preferences untouched) and reschedules, so that the
    next resume or timer refreshes it. Signed out: nothing. *)

val debug_import : t -> string -> (unit, error) result Fut.t
(** #dev/sync: a GoTrue session JSON (scripts/local-session.sh's output) adopted
    as if {!sign_in} had made it: {!Gotrue.decode_session} [~now] [~status:200],
    then written to Preferences, kept, [Signed_in], refresh rescheduled, the
    previous session logged out (the path {!sign_in} takes after the grant; a
    {!sign_in} running meanwhile ends with [Replaced]). Not JSON / not a session
    → [Error (Server (Malformed _))]; [Unconfigured] → [Error Not_configured] (a
    dev build needs a Google client id, any value, to be configured). *)
