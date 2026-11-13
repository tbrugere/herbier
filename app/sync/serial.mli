(** Steps run one after another: each starts once the previous one has resolved,
    whatever its result. *)

type t

val create : unit -> t

val run : t -> (unit -> 'a Fut.t) -> 'a Fut.t
(** Starts the step after the previous one has resolved; resolves with it. A
    step must not raise: one that does never resolves, and neither does any
    later step of [t] (the callers' steps are maps over results). *)
