(** One sync cycle as {!Engine} reports it: what triggered it, when, how far it
    went. Pure (test/sync copies it). *)

type cycle =
  | Push_stopped of Push.report * Outcome.stop  (** no pull ran *)
  | Pushed of Push.report * Pull.t

type t = {trigger : Schedule.trigger; started : Ptime.t; cycle : cycle}

val stop : t -> Outcome.stop option
(** Why the cycle stopped, [None] when it completed. *)

val pull_stop : t -> Outcome.stop option
(** Why the pull stopped, [None] when it completed or did not run. *)

val pulled_writes : t -> bool
(** The pull completed and wrote at least one row ({!Pull.writes} > 0). *)

val lines : t -> string list
(** The trigger, the push's counts, the pull's per-table counts (when it
    completed), the stop (when there is one). *)

val to_string : t -> string
(** {!lines} on one line, joined with ["; "]. *)
