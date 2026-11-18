(** 4k « À identifier »: the queue position (« À IDENTIFIER · i / n », «
    Suivante › »), 6i's « Identifier avec Pl@ntNet » under the observation card
    and its line, and what a proposal chosen in 6j leads to. Pure; nothing here
    raises or logs. *)

module Photo := Herbier_domain.Photo

type position = {
  index : int;
  total : int;
  next : Herbier_domain.Observation.t option;
}
(** [index] counts from 1. [next] is the observation after the current one,
    wrapping to the first; [None] when the current one is the only one. *)

val position :
  Herbier_domain.Observation.t ->
  Herbier_domain.Observation.t list ->
  position option
(** Where the observation (by id) is in the list; [None] when it is not there
    (already identified). *)

(** {1 6i: « Identifier avec Pl@ntNet » under the observation card} *)

val identify_label : string
(** {!Record_plan.identify_label}: ["Identifier avec Pl@ntNet"]. *)

val or_by_name : string
(** The separator's text: ["ou par le nom"] (the CSS upper-cases it). *)

val sent : Photo.t list -> Photo.t list
(** The photos sent: the first {!Herbier_identify.Organ.max_photos} (5) of the
    given list, in its order. *)

val identify_enabled : Identify_settings.gate -> photos:int -> bool
(** {!Record_plan.identify_enabled}: [Ready _] and [photos > 0]. *)

val no_photo_line : string
(** ["Cette observation n'a pas de photo à envoyer à Pl@ntNet."] *)

val offline_line : string
(** ["Hors-ligne : l'identification reviendra avec le réseau."] (4d's line
    without its second sentence, which is about a save). *)

val identify_line : Identify_settings.gate -> photos:int -> string option
(** The 12 px line under the button, first matching: [photos = 0] →
    [Some no_photo_line] (whatever the gate); [No_key] →
    [Some Identify_settings.no_key_line]; [Offline] → [Some offline_line];
    [Ready _], [Waiting] → [None]. *)

val identify_aria : Identify_settings.gate -> photos:int -> string
(** [photos = 0] → ["Identifier avec Pl@ntNet, aucune photo"]; else
    {!Record_plan.identify_aria} [gate]. *)

val caller : position option -> Identify.Caller.t
(** [Some {index; total; _}] → [Queue (Some {index; total})]; [None] (the
    observation is no longer in the queue, e.g. linked by a pull since) →
    [Queue None]. *)

(** {1 6j: what a chosen proposal leads to} *)

type after =
  | Stay  (** back to 6i, focus on the Identifier button *)
  | Resolve of Herbier_identify.Plantnet.proposal
      (** resolve the proposal through GBIF, then {!Record_plan.of_choice} *)

val equal_after : after -> after -> bool

val after_layer : Identify.Layer.outcome -> after
(** [Chosen p] → [Resolve p]; [Left], [None_matches] (back to 6i) and [Retake],
    [Keep_unnamed] (not offered to [Queue]) → [Stay]. *)
