type t = {el : Brr.El.t; bindings : Rb.binding list; ready : unit Fut.t}
(** What a screen hands the router: its root element, every binding it created,
    and when it shows its first content. The router keeps the list reachable
    while the screen is shown (see {!Rb}) and releases it when the screen is
    left.

    [ready] determines once the screen shows its first content (its store reads
    rendered, or their failure shown); {!now} for a screen built whole. Only a
    shared-hero transition waits for it, at most
    [Herbier_ui_model.Motion.ready_cap_ms]. It must determine at most once and
    must not fail. *)

val now : unit Fut.t
(** [Fut.return ()]. *)

val once : unit -> unit Fut.t * (unit -> unit)
(** [once ()] is a future and its setter: the first call of the setter
    determines the future, later calls do nothing. A screen that loads its
    content takes its [ready] from it (it may render again after a reload). *)
