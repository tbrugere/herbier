(** 4d's thumbnail row, pure: one slot per photo in the order the user added
    them. A shutter tap appends a [Pending] slot at once (the striped
    placeholder); its capture then fills it in place, or drops it. Gallery picks
    append [Ready] slots. Polymorphic in the shot so it stays native. *)

type ticket
(** A pending capture's handle: unique within the row that gave it (a counter in
    the row), never reused after {!fill} or {!drop}. *)

val equal_ticket : ticket -> ticket -> bool
val pp_ticket : Format.formatter -> ticket -> unit

type 'shot slot = Pending of ticket | Ready of 'shot

val equal_slot : ('shot -> 'shot -> bool) -> 'shot slot -> 'shot slot -> bool
(** Pending slots by ticket, Ready ones by the given shot equality. *)

type 'shot t

val empty : 'shot t

val slots : 'shot t -> 'shot slot list
(** In order, oldest first. *)

val begin_capture : 'shot t -> 'shot t * ticket
(** Appends a [Pending] slot at the end; its fresh ticket. *)

val fill : ticket -> 'shot -> 'shot t -> 'shot t
(** The pending slot of [ticket] becomes [Ready shot] at the same position (a
    later tap that settled first stays after it). A ticket not pending in this
    row (already filled or dropped): the row is unchanged. Never raises. *)

val drop : ticket -> 'shot t -> 'shot t
(** Removes the pending slot of [ticket] (a failed capture, or the ✕ of its
    placeholder); unknown ticket → unchanged. Never raises. *)

val is_pending : ticket -> 'shot t -> bool
(** Whether [ticket]'s slot is still pending in this row: [false] once it was
    filled or dropped. *)

val append : 'shot list -> 'shot t -> 'shot t
(** Gallery shots, [Ready], at the end, in order. *)

val remove : ('shot -> bool) -> 'shot t -> 'shot t
(** Removes the [Ready] slots whose shot satisfies the predicate (the ✕ of a
    thumbnail; the photos saved). Pending slots are kept. *)

val ready : 'shot t -> 'shot list
(** The shots of the [Ready] slots, in order: what Enregistrer saves and the
    observation is dated by (the first one). *)

val pending : 'shot t -> int
(** How many captures are still pending (for the tests; {!can_save} reads the
    same). *)

val can_save : 'shot t -> bool
(** Enregistrer's gate: at least one [Ready] slot and no [Pending] one. *)
