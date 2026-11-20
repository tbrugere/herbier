(** A short status line at the bottom of the screen. *)

val mount : unit -> unit
(** Once, at startup: appends to [document.body] the empty [div.toast-region]
    ([role="status"], [aria-live="polite"]) every toast is shown in, so that
    screen readers announce it. A {!show} before [mount] creates the region
    then. Never raises. *)

val show : ms:int -> string -> Rb.binding
(** Appends a [p.toast] holding the text to the region, removes it after [ms];
    [--toast-ms] is set inline to [ms] so that the CSS fade-out (its last 300
    ms) follows it. The binding, when released before, clears the timer and
    removes the element. Never raises. *)
