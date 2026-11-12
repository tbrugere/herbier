(** 4b: which observations the map shows, from the shared filters and the
    floating search. Pure (no store, no Brr), tested natively in [test/ui/]. *)

module Observation := Herbier_domain.Observation
module Plant_id := Herbier_domain.Ids.Plant_id
module Places := Herbier_domain.Places

type query =
  | Everything  (** blank search *)
  | Matching of {plants : Plant_id.t list; place : Places.cluster -> bool}
      (** [plants]: what [Search.plants_by_name] returned; [place]: does the
          place's name match ([Search.matches] on {!place_name}) *)

val place_name : Places.cluster -> string option
(** The text the search matches a place on: [Places.label] of its members when
    [Named s] or [Derived s]; [None] for [Coordinates] or no label. *)

val keep :
  filter:(Observation.t -> bool) ->
  query ->
  Places.cluster ->
  Observation.t ->
  bool
(** [filter o] (the screen passes [Journal_filter.keep] with the current
    {!State.filters}) and, for [Matching], [o]'s plant is in [plants] or
    [place cluster] holds. An unidentified observation passes a [Matching] query
    only through [place]. [keep ~filter query cluster] calls [place] at most
    once, however many observations it is then applied to. *)
