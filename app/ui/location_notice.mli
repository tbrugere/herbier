(** The one-time dialog of first opening: positions stay on the phone; each
    place-name source can be turned on in 4m, with what it sends to whom. *)

val show_once : App.t -> unit
(** Reads [Settings.Location_notice_seen]; [Ok (Some true)] → nothing. Otherwise
    ([None], [Some false], a [Decode] error) mounts a {!Widgets.Dialog} on
    [document.body] and shows it. Its buttons: « Choisir dans Réglages »
    ([Primary]) and « Compris » ([Secondary]). Either one writes
    [Location_notice_seen = true] (a write error is logged and the dialog still
    closes: it shows again at the next start), removes the element and releases
    its bindings (held until then); « Choisir dans Réglages » then
    [Route.go (Tab Settings)]. A read error (other than [Decode]) is logged and
    nothing is shown. Never raises. *)
