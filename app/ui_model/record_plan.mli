(** The pure part of 4d « Noter »: which plant the typed name means (and what a
    chosen proposal means, for 6j), what to suggest, when and where the
    observation is, and the controls' labels. *)

module Plant := Herbier_domain.Plant
module Observation := Herbier_domain.Observation

type target =
  | Existing of Plant.t
      (** a suggestion was picked, the name is a plant's, or the choice's owner
      *)
  | Free of string  (** a new 4g plant of that (trimmed) name *)
  | To_identify  (** no name: « À identifier » *)

type choice =
  | Target of target  (** as a typed name would save *)
  | Linked of {name : string; taxon : Herbier_refs.Sources.Gbif.Taxon.t}
      (** a new plant named [name], linked to [taxon] ([App.create_linked]) *)

val target : plants:Plant.t list -> chosen:Plant.t option -> string -> target
(** [chosen] (a tapped suggestion whose name is still the field's text) wins;
    else a plant of [plants] (the caller passes the live ones) whose display
    name or an alias equals the trimmed text, folding ASCII case only (« érable
    » is not « Érable »); else [Free], or [To_identify] when blank. *)

val of_choice : plants:Plant.t list -> Identify.Choice.t -> choice
(** What a save with this choice means (6j): {!Identify.Choice.owner}
    [~plants c] = [Some p] → [Target (Existing p)]; else
    {!Identify.Choice.taxon} [c] = [Some t] →
    [Linked {name = Choice.new_name c.proposal; taxon = t}]; else
    [Target ({!target} ~chosen:None (Choice.new_name c.proposal))]. *)

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

(** {1 4d's controls} *)

val save_label : string
(** ["Enregistrer"]: the save button's aria-label (an icon button, ✓). *)

val shutter_label : string
(** ["Prendre la photo"] *)

val flip_label : string
(** ["Changer de caméra"] *)

val pending_label : string
(** ["Photo en cours"]: the aria-label of a capture's placeholder thumbnail. *)

val cancel_pending_label : string
(** ["Annuler la photo en cours"]: the aria-label of a placeholder's ✕. *)
