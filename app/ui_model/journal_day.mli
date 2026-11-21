(** The pure part of 4c: grouping observations by local day and naming each
    day's place. *)

type 'a t = {date : Ptime.date; items : 'a list}

val group : date:('a -> Ptime.date) -> 'a list -> 'a t list
(** Consecutive items with the same [date] form one day, in the list's order
    (the store gives observations newest first, so days come newest first). *)

val place : Herbier_domain.Observation.t list -> string option
(** The day's place (handoff 4c), by {!Herbier_domain.Places.label}: its label
    (user-given or derived), or « Lieu inconnu »
    ({!Herbier_domain.Places.unknown_name}) when the day has a position but no
    name. [None] when the day has no label and no position. *)

val place_detail : Herbier_domain.Observation.t list -> string option
(** The line under the day's place (4c): {!Herbier_domain.Places.label_detail},
    a lieu-dit close to the day's derived name; [None] for a user's label. *)

val plant_name :
  (Herbier_domain.Ids.Plant_id.t * string) list ->
  Herbier_domain.Ids.Plant_id.t ->
  string
(** A row's title: the plant's name in [names], or ["Plante supprimée"] when it
    is not there. *)
