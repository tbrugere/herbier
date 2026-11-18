(** Overlays that have no history entry of their own (the identification layer),
    closed by Android back before the router walks history. Google Picker is not
    one of them: the router dismisses it first. Not thread-safe (single JS
    thread). *)

type t

val push : close:(unit -> unit) -> t
(** Registers an open overlay on top. [close] is what back does: it must close
    the overlay (and call {!remove}). *)

val remove : t -> unit
(** Unregisters it, wherever it is in the stack; idempotent. *)

val close_top : unit -> bool
(** Back: when the stack is not empty, removes the top overlay, calls its
    [close] and answers [true]; else [false]. [close]'s exceptions, but for
    [Out_of_memory] and [Stack_overflow], are caught and logged to the console.
*)
