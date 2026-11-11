(** The value of an [<input type="datetime-local">] (4h « Modifier » the date):
    wall-clock minutes in the phone's zone. Pure: the caller gives the zone. *)

val to_input : tz_offset_s:int -> Ptime.t -> string
(** ["2026-06-12T14:32"]: the seconds are dropped. *)

val of_input : offset:(Ptime.t -> int) -> string -> Ptime.t option
(** The instant whose wall-clock time in the zone is the input's: [offset t] is
    the zone's offset at [t] in seconds (east positive), so a date across a DST
    change takes that date's own offset. Accepts ["YYYY-MM-DDTHH:MM"] and
    ["…:SS"], digits only; [None] for anything else, and outside Ptime's range.
    Around a change, the offset in force before it wins: a repeated hour gives
    its first occurrence, and a skipped hour is read with that offset, which
    lands after the change (02:30 on a spring-forward night is 03:30 of the new
    offset), in every zone. *)
