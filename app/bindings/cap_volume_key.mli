(** Binding to Herbier's own [VolumeKey] Capacitor plugin
    (android/app/src/main/java/re/bruge/herbier/VolumeKeyPlugin.java, with
    MainActivity's dispatchKeyEvent; [globalThis.herbier.volumeKey], native
    only): the volume-down key as a shutter. While enabled and listened to, each
    press of volume down is consumed (no volume change, no volume panel) and
    sends one ["volumeDown"] event, holding the key sends no more; volume up and
    a disabled or unlistened key keep their system behaviour. *)

val enable : unit -> (unit, Cap_error.t) result Fut.t
(** [enable()]: volume down is consumed while a listener is registered. Plugin
    missing → [Unavailable "volumeKey"]. Never raises. *)

val disable : unit -> (unit, Cap_error.t) result Fut.t
(** [disable()]: volume down is the system's again (a press already consumed has
    its release consumed too). Never raises. *)

type listener
(** A registered listener (a [PluginListenerHandle]). *)

val on_volume_down : (unit -> unit) -> (listener, Cap_error.t) result Fut.t
(** Registers [f] for the plugin's ["volumeDown"] event (its payload is
    ignored). [f] is called from the JS event, outside any React update step. *)

val remove : listener -> (unit, Cap_error.t) result Fut.t
(** [handle.remove()]. *)
