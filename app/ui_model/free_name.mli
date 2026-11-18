(** 4g's reference block of a free-name plant once Pl@ntNet can name it (6k): «
    Identifier » beside « Chercher un nom », which observation's photos are
    sent, the Identifier button's state and line, and what a proposal chosen in
    the layer does to the plant. Pure; nothing here raises or logs, and no text
    names CORS, an origin, localhost, exposing or the api-key parameter. *)

module Photo := Herbier_domain.Photo
module Observation := Herbier_domain.Observation

val identify_label : string
(** ["Identifier"] (6k). *)

val search_label : string
(** ["Chercher un nom"]; opens 4i for this plant (Route.Link_species). *)

type sent = {observation : Observation.t; photos : Photo.t list}

val equal_sent : sent -> sent -> bool

val sent : observations:Observation.t list -> photos:Photo.t list -> sent option
(** The one observation whose previews « Identifier » sends (Pl@ntNet assumes
    one individual per request): among [observations] with [deleted_at = None]
    and at least one photo of [photos] whose [observation_id] is its id, the
    newest by [at], ties broken by the greater id (Observation_id.compare); its
    photos (those of [photos] with that [observation_id] and
    [deleted_at = None]; a photo of another observation, or of none of
    [observations], never counts) in {!Herbier_domain.Photo.compare_strip}
    order, the first {!Herbier_identify.Organ.max_photos} (5). [None] when no
    such observation. Input order does not matter. *)

val identify_enabled : Identify_settings.gate -> photos:int -> bool
(** {!To_identify.identify_enabled}: [Ready _] and [photos > 0]. *)

val no_photo_line : string
(** ["Aucune observation de cette plante n'a de photo à envoyer à Pl@ntNet."] *)

val identify_line : Identify_settings.gate -> photos:int -> string option
(** The 12 px line under the two buttons, first matching: [photos = 0] →
    [Some no_photo_line] (whatever the gate); [No_key] →
    [Some Identify_settings.no_key_line] (online or offline); [Offline],
    [Ready _], [Waiting] → [None] (offline, 4g's own text,
    {!Network_text.unlinked_offline}, already says it after « Aucune espèce de
    référence liée. »). *)

val identify_aria : Identify_settings.gate -> photos:int -> string
(** {!To_identify.identify_aria}: [photos = 0] →
    ["Identifier avec Pl@ntNet, aucune photo"]; [Offline] →
    ["… indisponible hors-ligne"]; [No_key] → ["… clé API manquante"]; else
    ["Identifier avec Pl@ntNet"]. *)

type link =
  | Link of {name : string; taxon : Herbier_refs.Sources.Gbif.Taxon.t}
      (** [App.link ~name plant taxon]: the plant takes [name], its free name
          becoming an alias (Plant_link.apply) *)
  | Unknown_to_gbif  (** GBIF has no species for it: nothing written *)
  | Gbif_unavailable
      (** GBIF did not answer and Pl@ntNet gave no id: nothing written *)

val equal_link : link -> link -> bool
val pp_link : Format.formatter -> link -> unit

val link : Identify.Choice.t -> link
(** What « Lier » on this choice writes, once [App.resolve_choice] answered (the
    caller passes [Choice.resolved (Choice.v p) r]):
    - [Choice.taxon c = Some t] →
      [Link {name = Choice.new_name c.proposal; taxon = t}] (GBIF's taxon when
      [Resolved]; Pl@ntNet's own when GBIF is [Unavailable] or not asked yet and
      the proposal has a gbif id);
    - [None] with [resolution = Some Unknown] → [Unknown_to_gbif];
    - [None] otherwise (pending or [Unavailable _], no gbif id) →
      [Gbif_unavailable].

    Never raises. The name is Pl@ntNet's first French name, else its Latin name
    without author: never the taxon's GBIF vernacular. *)

val problem : link -> string option
(** The line under the fiche's hero (species.ml's [problem]): [Link _] → [None];
    [Unknown_to_gbif] →
    [Some "GBIF ne connaît pas cette espèce : la fiche garde son nom libre."];
    [Gbif_unavailable] →
    [Some "GBIF n'a pas répondu : la fiche n'a pas été liée. Réessayez avec le
     réseau."]. *)

val link_failed : string
(** ["La fiche n'a pas pu être liée."] ([App.link]'s [Store _]; the same text as
    4i's Link_plant). *)

val plant_gone : string
(** ["Cette plante n'est plus dans l'herbier."] ([App.link]'s [Plant_gone]). *)
