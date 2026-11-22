(** What deleting a plant or an observation takes with it, as 5a, 4h and the
    long-press of 4a / 4c say and save it. Pure: the ids are the live dependents
    as the caller read them; the edits are {!Herbier_store.Cascade}'s. *)

module Ids := Herbier_domain.Ids

type plant = {
  plant : Herbier_domain.Plant.t;
  observations : Ids.Observation_id.t list;
      (** {!Herbier_store.Observations.of_plant} *)
  photos : Ids.Photo_id.t list;  (** {!Herbier_store.Photos.of_plant} *)
  tags : Ids.Tag_id.t list;  (** {!Herbier_store.Tags.of_plant} *)
  in_drive : int;  (** how many of [photos] satisfy {!has_drive_file} *)
}

type observation = {
  observation : Ids.Observation_id.t;
  photos : Ids.Photo_id.t list;  (** {!Herbier_store.Photos.of_observation} *)
  in_drive : int;  (** how many of [photos] satisfy {!has_drive_file} *)
}

val has_drive_file : Herbier_domain.Photo.t -> bool
(** [original_target = Drive] and a non-blank [drive_file_id]: the photo's
    original is a Drive file Herbier uploaded, which its delete sends to Drive's
    bin (the trigger of {!Herbier_store.Schema}'s migration 11). A photo kept «
    Dans Herbier seulement », or still waiting for its upload (cancelled by the
    delete), has none. *)

val plant_of :
  Herbier_domain.Plant.t ->
  observations:Herbier_domain.Observation.t list ->
  photos:Herbier_domain.Photo.t list ->
  tags:Herbier_domain.Tag.t list ->
  plant
(** The rows as read by the queries named in {!plant}'s fields, kept as ids. *)

val observation_of :
  Ids.Observation_id.t -> photos:Herbier_domain.Photo.t list -> observation
(** The photos as read by {!Herbier_store.Photos.of_observation}, kept as ids.
*)

(** A confirmation's answer: the value of each button of its dialog. *)
type choice = Delete | Keep

val plant_title : Herbier_domain.Plant.t -> string
(** [Supprimer « <display_name> » ?] *)

val plant_text : plant -> string
(** By [n], the number of observations, and [p], of photos:
    - n = 0 → [La fiche quitte l'herbier.] (whatever p);
    - n ≥ 1, p = 0 → [La fiche et <its> quittent l'herbier.];
    - n ≥ 1, p ≥ 1 →
      [La fiche, <its> et <ses|leurs> <p photo(s)> quittent l'herbier.] ([ses]
      when n = 1, else [leurs]; [<p photo(s)>] is
      {!Fr_text.plural}[ p "photo" "photos"]), then the bin sentence of
      [in_drive] among [p],

    where [<its>] is [son observation] (n = 1) or [ses <n> observations]. The
    tags change nothing.

    The bin sentence, after a space, for [d] originals in Drive among [p]
    photos: d = 0 → none; d = p = 1 →
    [Son original va dans la corbeille de Google Drive (récupérable 30 jours).];
    d = p > 1 →
    [Leurs originaux vont dans la corbeille de Google Drive (récupérables 30
     jours).]; d = 1 < p →
    [L'original déjà envoyé va dans la corbeille de Google Drive (récupérable 30
     jours).]; 1 < d < p →
    [Les <d> originaux déjà envoyés vont dans la corbeille de Google Drive
     (récupérables 30 jours).] *)

val plant_action : plant -> string
(** 5a's footer button: n = 0 → [Supprimer la plante ›]; else
    [Supprimer la plante et <its> ›]. *)

val plant_failure : string
(** [La plante n'a pas pu être supprimée.] *)

val plant_edits : at:Ptime.t -> plant -> Herbier_store.Outbox.edit list
(** [Cascade.plant ~at ~photos ~observations ~tags plant.id], nothing else. *)

val observation_title : string
(** [Supprimer cette observation ?] *)

val observation_text : observation -> string
(** p = 0 → [Elle quitte l'herbier et le journal.]; p ≥ 1 →
    [Elle quitte l'herbier avec ses <p photo(s)>.] then {!plant_text}'s bin
    sentence of [in_drive] among p. *)

val observation_failure : string
(** [L'observation n'a pas pu être supprimée.] *)

val observation_edits :
  at:Ptime.t -> observation -> Herbier_store.Outbox.edit list
(** [Cascade.observation ~at ~photos observation], nothing else. *)

val photo_title : string
(** 5e « Retirer d'Herbier »: [Retirer cette photo d'Herbier ?] *)

val photo_text : in_drive:bool -> string
(** [Elle quitte la fiche et l'observation.], then, when [in_drive] (the photo's
    {!has_drive_file}),
    [Son original va dans la corbeille de Google Drive (récupérable 30 jours).]
*)
