(** What a pulled row does to the local one (architecture §4, pull). Last write
    wins in the server's order: the device's own [updated_at] is never compared
    with the pulled row's. Outbox wins: a row with a pending outbox entry keeps
    its local version. *)

type decision =
  | Insert  (** no local row: write the remote one *)
  | Replace
      (** the local row differs from the remote one and has no pending entry:
          write the remote one ([deleted_at] and [updated_at] included) *)
  | Unchanged  (** the local row equals the remote one: write nothing *)
  | Keep_local  (** a pending outbox entry: write nothing *)

val equal_decision : decision -> decision -> bool

val pp_decision : Format.formatter -> decision -> unit
(** The constructor's name: [Insert], [Replace], [Unchanged], [Keep_local]. *)

val decide :
  equal:('a -> 'a -> bool) -> pending:bool -> local:'a option -> 'a -> decision
(** In this order: [local = None] → [Insert], whatever [pending] (an entry
    without its row cannot exist, and the remote row is the only copy);
    [pending] → [Keep_local]; [equal local remote] → [Unchanged]; else
    [Replace], also when the remote [updated_at] is older than the local one.
    [pending] means an outbox entry for the row that is not parked: a parked
    entry is never pushed, so its row takes the remote version. Pure, total,
    never raises. *)
