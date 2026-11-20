(** Overlays that have no history entry of their own (the identification layer,
    6d, 4d's viewfinder taking a photo for it), closed by Android back before
    the router walks history, with what each draws under the system bars. Google
    Picker is not one of them: the router dismisses it first. Not thread-safe
    (single JS thread). *)

type t

val push :
  surface:Herbier_ui_model.System_bars.surface -> close:(unit -> unit) -> t
(** Registers an open overlay on top, drawing [surface] under the system bars.
    [close] is what back does: it must close the overlay (and call {!remove}).
*)

val remove : t -> unit
(** Unregisters it, wherever it is in the stack; idempotent. *)

val close_top : unit -> bool
(** Back: when the stack is not empty, removes the top overlay, calls its
    [close] and answers [true]; else [false]. [close]'s exceptions, but for
    [Out_of_memory] and [Stack_overflow], are caught and logged to the console.
*)

val surfaces : unit -> Herbier_ui_model.System_bars.surface list
(** The open overlays' surfaces, top first. *)

val on_change : (unit -> unit) -> unit
(** [f] is called after each {!push}, each {!remove} that removed an overlay and
    each {!close_top} that removed one (before its [close]). A plain callback,
    not a React signal: overlays are removed from screens' releases, which run
    inside the router's update step, where setting a signal raises. [f]'s
    exceptions, but for [Out_of_memory] and [Stack_overflow], are caught and
    logged. One observer; a second call replaces it: only {!System_bars.start}
    registers one. *)
