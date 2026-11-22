(** 4h Observation's pure parts: the arrival from 4d's Enregistrer, « Identifier
    avec Pl@ntNet » on an « À identifier » observation, and what a proposal
    chosen in the identification layer writes (shared with 4k's 6j). Pure;
    nothing here raises or logs. *)

module Plant := Herbier_domain.Plant
module Observation := Herbier_domain.Observation
module Plant_id := Herbier_domain.Ids.Plant_id
module Taxon := Herbier_refs.Sources.Gbif.Taxon

(** {1 Arrival} *)

type arrival =
  | Opened  (** from the journal, a fiche, the map, 5b's back… *)
  | Recorded of {identify : bool}  (** from 4d's Enregistrer *)

val toast : arrival -> layer:bool -> Plant.t option -> string option
(** The short confirmation shown on arrival. [Opened] → [None]; [Recorded _]
    with [layer = true] (the layer opened at arrival) → [None]; else [Some p] →
    [Some ("Enregistrée · ajoutée à " ^ p.display_name)], [None] (« À identifier
    », or a plant not found) → [Some "Enregistrée · à identifier"]. *)

val toast_ms : int
(** [2500]. *)

val opens_layer :
  arrival -> Observation.t -> Identify_settings.gate -> photos:int -> bool
(** Whether 4h opens the identification layer as soon as its data is in:
    [Recorded {identify = true}], {!identifiable},
    {!To_identify.identify_enabled} [gate ~photos]. Re-checked at 4h (the
    network may have dropped since Enregistrer): any other case → [false], the
    button stays for a tap. *)

(** {1 « Identifier avec Pl@ntNet » (4h)} *)

val identifiable : Observation.t -> bool
(** The button shows: [plant_id = None] (« À identifier »). An observation on a
    plant has « Changer d'espèce » (5c), and a free-name plant has 6k on its
    fiche. *)

val identify_line : Identify_settings.gate -> photos:int -> string option
(** The line under the button, first matching: [photos = 0] →
    [Some To_identify.no_photo_line]; [Offline] →
    [Some To_identify.offline_line]; [No_key], [Ready _], [Waiting] → [None]
    (unlike 6i, no key-hint line: the aria-label, {!To_identify.identify_aria},
    names the missing key). *)

val by_name_label : string
(** ["Par le nom"]: 4h's button under « Identifier avec Pl@ntNet » for an « À
    identifier » observation (opens 4k). *)

val map_label : string
(** ["Corriger la position sur la carte"]: the mini-map tap's aria-label (it
    opens 5b). *)

(** {1 What a chosen proposal writes (4h and 4k's 6j)} *)

type write =
  | Attach of Plant_id.t  (** the observation moves onto this plant of mine *)
  | Create_free of Plant.t
      (** a new free-name plant, then the observation onto it *)
  | Create_linked of {plant : Plant.t; taxon : Taxon.t}
      (** a new plant linked to [taxon] ([App.create_linked]), with the
          observation onto it in the same save *)

val equal_write : write -> write -> bool

val write :
  at:Ptime.t -> new_plant:Plant_id.t -> Record_plan.choice -> write option
(** [Target (Existing p)] → [Some (Attach p.id)]; [Target (Free name)] →
    [Some (Create_free (Plant.v ~id:new_plant ~at name))];
    [Linked {name; taxon}] →
    [Some (Create_linked {plant = Plant_link.create ~id:new_plant ~at ~name
     taxon; taxon})]; [Target To_identify] → [None] (a proposal without a name:
    the caller shows {!no_name}). [new_plant] is used only by the two
    [Create_*]. *)

val chosen :
  at:Ptime.t ->
  new_plant:Plant_id.t ->
  plants:Plant.t list ->
  Identify.Choice.t ->
  write option
(** [write ~at ~new_plant (Record_plan.of_choice ~plants c)]: what a proposal
    chosen in the layer writes, once GBIF resolved it
    ({!Identify.Choice.resolved}). [plants] are the live plants. *)

val no_name : string
(** ["Cette proposition n'a pas de nom."]: the line shown when {!chosen} is
    [None]. *)

val plant_of : write -> Plant_id.t
(** The plant the observation is on once [write] is saved: [Attach id] → [id];
    [Create_free p], [Create_linked {plant = p; _}] → [p.id]. *)
