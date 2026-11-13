(** The pure part of 4d « Noter »: which plant the typed name means, what to
    suggest, and when and where the observation is. *)

module Plant := Herbier_domain.Plant
module Observation := Herbier_domain.Observation

type target =
  | Existing of Plant.t
      (** a suggestion was picked, or the name is a plant's *)
  | Free of string  (** a new 4g plant of that (trimmed) name *)
  | To_identify  (** no name: « À identifier » *)

val target : plants:Plant.t list -> chosen:Plant.t option -> string -> target
(** [chosen] (a tapped suggestion whose name is still the field's text) wins;
    else a plant of [plants] (the caller passes the live ones) whose display
    name or an alias equals the trimmed text, folding ASCII case only (« érable
    » is not « Érable »); else [Free], or [To_identify] when blank. *)

val seen_here :
  here:Observation.position ->
  Observation.t list ->
  Plant.t list ->
  Plant.t list
(** « Vues ici »: the plants with an observation within 500 m of [here]
    ({!Herbier_domain.Places.within}), nearest first (by their nearest
    observation), each once. The caller passes live observations and plants;
    observations without plant or position, and plants not in the list, are
    skipped. *)

val when_where :
  now:Ptime.t ->
  fix:Observation.position option ->
  (Ptime.t option * Observation.position option) list ->
  Ptime.t * Observation.position option
(** The observation's [at] and [position] from the first photo's EXIF date and
    position (a gallery photo taken earlier, elsewhere). Without an EXIF date,
    [at] is [now]. Without an EXIF position, [position] is the GPS [fix] only
    when [at] is within {!fix_window_s} of [now]: an older photo stripped of its
    GPS is not placed where the phone is today, it gets no position. No photo:
    [now] and [fix]. *)

val fix_window_s : float
(** [600.]: how far a photo's date may be from [now] for the GPS fix to stand
    for where it was taken. *)
