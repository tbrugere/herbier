(** Binding to Herbier's own [ForegroundRun] Capacitor plugin
    (android/app/src/main/java/re/bruge/herbier/ForegroundRunPlugin.java and
    ForegroundRunService.java, [globalThis.herbier.foregroundRun], native only):
    a foreground service of type dataSync with one ongoing, silent notification
    (a title, an optional text, a progress bar, an optional action), which keeps
    the app's process at foreground priority while the WebView runs a long job.
    The notification's action sends an ["interrupt"] event; the service never
    acts on the job itself. *)

type notice = {
  title : string;  (** non-empty *)
  text : string option;  (** the second line; [None] sends no [text] key *)
  value : int;  (** [0 <= value <= max] *)
  max : int;  (** [>= 0] *)
  action : string option;
      (** the label of the one action, which sends ["interrupt"]; [None] sends
          no [action] key and shows no action *)
}

(** [notifications] of {!start}'s answer. *)
type notifications = Granted | Denied

val start : notice -> (notifications, Cap_error.t) result Fut.t
(** [start({title, text?, value, max, action?})] →
    [{notifications: "granted" | "denied"}]. On Android 13+ asks for
    POST_NOTIFICATIONS when not granted (resolves after the user's answer, the
    service started either way: [Denied] = the service runs, its notification
    hidden). A second [start] while started updates the notice. Rejections:
    ["INVALID_ARGUMENT"] (empty [title], [max < 0], [value] outside [0..max], an
    empty [action]), ["START_NOT_ALLOWED"] (Android refused to start a
    foreground service: the app was in the background). A resolved value without
    [notifications] or with another value →
    [Error (Unexpected "notifications")]. Plugin missing →
    [Unavailable "foregroundRun"]. Never raises. *)

val update : notice -> (unit, Cap_error.t) result Fut.t
(** [update({title, text?, value, max, action?})]: the notification shows
    [notice] (when not started, only kept: a {!start} still waiting for the
    permission answer shows it; a later {!start} shows its own notice).
    ["INVALID_ARGUMENT"] as {!start}. Never raises. *)

val stop : unit -> (unit, Cap_error.t) result Fut.t
(** [stop()]: the service stopped and its notification removed; nothing started
    is [Ok ()]. A {!start} still waiting for the permission answer does not
    start the service. Never raises. *)

type reason =
  | User  (** the notification's action was tapped *)
  | Timeout
      (** Android ended the service (Android 15+, dataSync's time budget); the
          service has stopped itself *)

type listener
(** A registered listener (a [PluginListenerHandle]). *)

val on_interrupt : (reason -> unit) -> (listener, Cap_error.t) result Fut.t
(** Registers [f] for the plugin's ["interrupt"] event, [{reason}]: ["timeout"]
    → [Timeout]; ["user"], another value or no [reason] → [User] (an interrupt
    is never dropped). [f] is called from the JS event, outside any React update
    step. *)

val remove : listener -> (unit, Cap_error.t) result Fut.t
(** [handle.remove()]. *)
