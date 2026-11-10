(** The pure part of 4c: grouping observations by local day and naming each
    day's place. *)

type 'a t = {date : Ptime.date; items : 'a list}

val group : date:('a -> Ptime.date) -> 'a list -> 'a t list
(** Consecutive items with the same [date] form one day, in the list's order
    (the store gives observations newest first, so days come newest first). *)

val place : Herbier_domain.Observation.t list -> string option
(** The day's place (handoff 4c), by {!Herbier_domain.Places.label}: its label,
    or the mean position as ["48.0633, 7.0081"]. [None] when the day has no
    label and no position. *)
