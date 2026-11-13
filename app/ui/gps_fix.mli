(** The one fix a new observation takes (4d, 4j): high accuracy, 20 s timeout, a
    cached fix of at most 30 s accepted. The observation never waits for it. *)

val start : on_error:(string -> unit) -> unit -> Gps.t React.signal
(** Starts the fix: [Searching], then [Fix p] or [No_fix]. [on_error] gets the
    plugin's error text on [No_fix]. Never raises. *)
