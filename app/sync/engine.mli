(** Runs sync cycles (push, then pull when the push completed) over
    {!Net.Transport} and {!Herbier_store.Db}, as {!Cycle.Schedule} decides. Logs
    each cycle to the console (["sync: …"], never a token). *)

type t

val create :
  db:Herbier_store.Db.t -> auth:Auth.t -> on_cycle:(Cycle.Report.t -> unit) -> t
(** No IO, no listener. Triggers before {!start} are ignored (dev pages build
    apps that never sync). *)

val start : t -> unit
(** Once per process (a second call is ignored): registers
    [Cap_app.on_state_change] ([Active] → [Resume], [Inactive] → [Backgrounded];
    registration failure → console warning), then [Start]. *)

val local_write : t -> unit
val signed_in : t -> unit

val sync_now : t -> unit
(** [Local_write], [Signed_in], [Manual] triggers. Never raise; callable from
    any callback, never from a React update step.

    A cycle stopped on [Unauthorized] awaits [Auth.refresh_now] (its result
    logged) before the schedule's next action, so a revoked session turns the
    next cycle into [Signed_out]. [Wait d] arms one timer (any previous one
    cleared) that sends [Retry_timer]; [Run] and [Cancel_timer] clear it.
    [on_cycle] is called once per cycle, after the schedule's action was
    applied, from a future's callback (outside any update step). *)

val state : t -> Cycle.Schedule.state
val last : t -> Cycle.Report.t option
