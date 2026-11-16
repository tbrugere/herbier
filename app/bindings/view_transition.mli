(** [document.startViewTransition] (View Transitions API, Chrome 111+), absent
    from Brr 0.0.9. Its promises are mapped to futures that never fail: a
    skipped transition is an ordinary end, and their rejections are handled so
    none reaches the console as unhandled. A skip for another reason than a
    newer transition or a raising update (a duplicate name, a hidden document, a
    timeout) is logged as a console warning with the error's name and message.
*)

type t

val supported : unit -> bool
(** [document.startViewTransition] is a function, read at each call (a test
    driver may remove it to exercise the fallback). *)

val start : (unit -> unit Fut.t) -> t option
(** [start update] starts a transition whose DOM update is [update ()]: called
    by the browser once the old state is captured, the new state captured when
    its future determines. [None] when not {!supported}: [update] is then NOT
    called. An exception raised by [update] is logged to the console
    (["view transition: update"] and the exception) and the transition is
    skipped; it never propagates into the browser's callback. *)

val finished : t -> [`Finished | `Skipped] Fut.t
(** Determines once the transition is over: [`Finished] when its animation ran
    ([ready] fulfilled, then [finished] settled), [`Skipped] when it was skipped
    ([ready] rejected), in that case only after the update callback has run
    ([finished] settled), so nothing the update does comes after it. Never
    fails. *)
