(** One sync cycle as {!Engine} reports it: what triggered it, when, how far it
    went. Pure. *)

type cycle =
  | Push_stopped of Push.report * Outcome.stop  (** no pull ran *)
  | Pushed of Push.report * Pull.t
  | Held of string * Pull.t
      (** the push held back by the keep-alive (why): nothing pushed, the pull
          ran *)

type t = {trigger : Schedule.trigger; started : Ptime.t; cycle : cycle}

val stop : t -> Outcome.stop option
(** Why the cycle stopped, [None] when it completed: for [Held], the pull's
    stop, else [Outcome.Held why]. *)

val pull_stop : t -> Outcome.stop option
(** Why the pull stopped, [None] when it completed or did not run. *)

val pulled_writes : t -> bool
(** The pull completed and wrote at least one row ({!Pull.writes} > 0). *)

val lines : t -> string list
(** The trigger, the push's counts (for [Held], the hold), the pull's per-table
    counts (when it completed), the stop (when there is one, but for [Held] only
    the pull's: the hold is not repeated). *)

val to_string : t -> string
(** {!lines} on one line, joined with ["; "]. *)
