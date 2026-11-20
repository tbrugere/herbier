(** 4k « À identifier »: the queue position (« À IDENTIFIER · i / n », «
    Suivante › »), 6i's « Identifier avec Pl@ntNet » under the observation card
    and its line (what a proposal chosen in 6j leads to is
    {!Identify.Layer.after_close}). Pure; nothing here raises or logs. *)

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
(** ["Identifier avec Pl@ntNet"] *)

val or_by_name : string
(** The separator's text: ["ou par le nom"] (the CSS upper-cases it). *)

val sent : Photo.t list -> Photo.t list
(** The photos sent: the first {!Herbier_identify.Organ.max_photos} (5) of the
    given list, in its order. *)

val identify_enabled : Identify_settings.gate -> photos:int -> bool
(** [Ready _] and [photos > 0]. *)

val no_photo_line : string
(** ["Cette observation n'a pas de photo à envoyer à Pl@ntNet."] *)

val offline_line : string
(** ["Hors-ligne : l'identification reviendra avec le réseau."] (the line under
    4k's 6i and 4h's Identifier). *)

val identify_line : Identify_settings.gate -> photos:int -> string option
(** The 12 px line under the button, first matching: [photos = 0] →
    [Some no_photo_line] (whatever the gate); [No_key] →
    [Some Identify_settings.no_key_line]; [Offline] → [Some offline_line];
    [Ready _], [Waiting] → [None]. *)

val identify_aria : Identify_settings.gate -> photos:int -> string
(** The button's aria-label, first matching: [photos = 0] →
    [identify_label ^ ", aucune photo"]; [Offline] →
    [identify_label ^ ", indisponible hors-ligne"]; [No_key] →
    [identify_label ^ ", clé API manquante"]; [Ready _], [Waiting] →
    {!identify_label}. *)

val caller : position option -> Identify.Caller.t
(** [Some {index; total; _}] → [Queue (Some {index; total})]; [None] (the
    observation is no longer in the queue, e.g. linked by a pull since) →
    [Queue None]. *)
