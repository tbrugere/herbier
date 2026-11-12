(** The filter chips shared by 4c and 4b (handoff: filters « partagés
    Collection/Carte/Journal »): one per year present, « À identifier · n », one
    per tag; all of them read and toggle {!State.filters}. *)

type chip = Year of int | To_identify of int | Tag of Herbier_domain.Tag.t

val chips :
  year_of:(Herbier_domain.Observation.t -> int) ->
  State.filters ->
  Herbier_domain.Observation.t list ->
  Herbier_domain.Tag.t list ->
  chip list
(** {!Journal_filter.year_chips}, then {!Journal_filter.to_identify_chip}, then
    the tags in the given order. *)

val el : State.t -> chip -> Brr.El.t * Rb.binding list
(** A {!Widgets.Chip.filter} that shows whether its filter is on and toggles it.
*)
