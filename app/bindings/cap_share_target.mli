(** Binding to [@capgo/capacitor-share-target]
    ([globalThis.herbier.shareTarget]): content other apps share to Herbier
    through the Android share sheet (the manifest's [SEND text/plain]). *)

type listener
(** A registered listener (a [PluginListenerHandle]). *)

type share = {
  title : string;  (** [EXTRA_SUBJECT], else [EXTRA_TITLE]; [""] when none. *)
  texts : string list;
      (** [EXTRA_TEXT], as the plugin lists it (0 or 1 element on Android). *)
}
(** The event's [files] are not read: the manifest declares text only. *)

val on_share_received : (share -> unit) -> (listener, Cap_error.t) result Fut.t
(** Registers [f] for [shareReceived]. [f] is called from the JS event, outside
    any reactive update step. An event whose [title] is not a string or whose
    [texts] is not an array is dropped with a console warning naming the field
    (never the content: a share may carry user data); a non-string element of
    [texts] is skipped. Never raises into JS; exceptions raised by [f] are not
    caught here. A share that cold-starts the app is retained by the plugin and
    delivered once, to the first listener registered. *)

val remove : listener -> (unit, Cap_error.t) result Fut.t
(** [handle.remove()]. *)
