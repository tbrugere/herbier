(** The retry delay sync shares: a refresh that failed transiently
    ({!Auth.Lifecycle}) and a cycle that stopped on a retried outcome
    ({!Cycle.Schedule}). *)

val delay : attempt:int -> Ptime.Span.t
(** 10 s × 2^(attempt - 1), at most 300 s; [attempt <= 1] → 10 s; no overflow
    for any [attempt]. *)
