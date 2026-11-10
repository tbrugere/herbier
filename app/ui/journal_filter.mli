(** The pure part of 4c's filters: which observations are listed and which chips
    are shown. [year_of] is an observation's local year (the screen passes
    {!Fr_date.year} at the observation's own offset). No Brr, tested natively in
    [test/ui/]. *)

module Observation := Herbier_domain.Observation

val keep :
  year_of:(Observation.t -> int) ->
  year:int option ->
  to_identify_only:bool ->
  tagged:Herbier_domain.Ids.Plant_id.t list list ->
  Observation.t ->
  bool
(** In that year ([None]: every year), without a plant when [to_identify_only],
    and, when tags are selected ([tagged] as in
    {!Collection_filter.has_all_tags}, [[]] for none), of a plant carrying all
    of them: an observation without a plant is then left out. *)

val year_chips :
  year_of:(Observation.t -> int) ->
  year:int option ->
  Observation.t list ->
  int list
(** The years of the observations, newest first, each once, plus the selected
    [year] even when no observation is left in it, so its chip can be turned
    off. *)

val to_identify_chip : to_identify_only:bool -> Observation.t list -> int option
(** The count of « À identifier · n »: [None] (no chip) when no observation is
    without a plant, unless the filter is on, so its chip can be turned off. *)
