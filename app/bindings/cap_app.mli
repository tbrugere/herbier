(** Binding to [@capacitor/app] ([globalThis.herbier.app]): app state changes
    and URLs that open the app. *)

type listener
(** A registered listener (a [PluginListenerHandle]). *)

(** [appStateChange]'s [isActive]: [Active] in the foreground, [Inactive] when
    backgrounded. *)
type state = Active | Inactive

val on_state_change : (state -> unit) -> (listener, Cap_error.t) result Fut.t
(** Registers [f] for [appStateChange]. [f] is called from the JS event, outside
    any reactive update step. An event without a boolean [isActive] is dropped
    with a console warning (never raises into JS). Exceptions raised by [f] are
    not caught here. *)

val on_url_open : (string -> unit) -> (listener, Cap_error.t) result Fut.t
(** Registers [f] for [appUrlOpen] with the event's [url]. Same rules; an event
    without a string [url] is dropped. The URL comes from outside the app and is
    untrusted: classify it before any use. Fires only for intents the manifest
    declares; a URL that cold-starts the app is not reported (that needs
    [getLaunchUrl]). *)

val remove : listener -> (unit, Cap_error.t) result Fut.t
(** [handle.remove()]: the callback is no longer called once this resolves. *)
