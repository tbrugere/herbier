(** When the engine runs a cycle (push then pull). Pure state machine: one cycle
    at a time (push and pull never overlap, architecture §4), a trigger during a
    cycle runs exactly one more after it, failures back off. *)

type trigger =
  | Start  (** app start *)
  | Resume  (** back in the foreground *)
  | Local_write  (** a commit appended an outbox entry *)
  | Signed_in
  | Manual  (** #dev/sync « Synchroniser » *)
  | Retry_timer  (** the backoff timer fired *)
  | Backgrounded
[@@deriving eq, show]

type action =
  | Run of trigger  (** start a cycle now, reported as caused by [trigger] *)
  | Wait of Ptime.Span.t  (** arm the retry timer *)
  | Cancel_timer  (** clear the retry timer, run nothing *)
  | Nothing
[@@deriving eq, show]

type state =
  | Idle of {attempt : int}
  | Running of {attempt : int; again : trigger option; background : bool}
      (** [again]: the latest trigger received during the cycle, which runs one
          more after it; [background]: the app went to the background during the
          cycle *)
  | Waiting of {attempt : int}
[@@deriving eq, show]

val trigger_to_string : trigger -> string
val state_to_string : state -> string

val initial : state
(** [Idle {attempt = 0}] *)

val trigger : state -> trigger -> state * action
(** - [Idle] + [Retry_timer] → unchanged, [Nothing] (stale timer).
    - [Idle] + [Backgrounded] → unchanged, [Nothing].
    - [Idle] + any other [t] → [Running {again = None; background = false}],
      [Run t].
    - [Running] + [Backgrounded] → [background = true], [Nothing].
    - [Running] + [Retry_timer] → unchanged, [Nothing].
    - [Running] + any other [t] →
      [Running {again = Some t; background = false}], [Nothing].
    - [Waiting] + [Backgrounded] → [Idle] (attempt kept), [Cancel_timer].
    - [Waiting] + any other [t] ([Retry_timer] included) →
      [Running {again = None; background = false}] (attempt kept), [Run t]; the
      engine clears its timer before running. *)

val finished : state -> Outcome.stop option -> state * action
(** End of a cycle ([None] = completed). Only meaningful in [Running]; in any
    other state → unchanged, [Nothing].
    - completed → attempt 0; [again = Some t] → [Running], [Run t]; else [Idle],
      [Nothing].
    - stopped, [Outcome.retries] false ([Signed_out]) → [Idle {attempt = 0}],
      [Nothing], [again] dropped.
    - stopped, retried: attempt + 1; [background] → [Idle], [Nothing] (no timer
      in the background, as [Waiting] + [Backgrounded]; the next [Resume] runs
      at once), [again] dropped; else [again = Some t] → [Running], [Run t];
      else [Waiting], [Wait (retry_delay ~attempt)].
    - [background] is kept by a completed cycle's [again] rerun. *)

val retry_delay : attempt:int -> Ptime.Span.t
(** 10 s × 2^(attempt - 1), at most 300 s; [attempt <= 1] → 10 s; no overflow
    for any [attempt]. *)
