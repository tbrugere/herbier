(** The pure part of 4d « Noter »: which plant the typed name or the choice
    means, what to suggest, when and where the observation is, and 4d's part of
    identification (6a's button, the kept answer, 6e's card, the « + <organe> »
    viewfinder pill, the layer's outcome). *)

module Plant := Herbier_domain.Plant
module Observation := Herbier_domain.Observation
module Organ := Herbier_identify.Organ
module Plantnet := Herbier_identify.Plantnet

type target =
  | Existing of Plant.t
      (** a suggestion was picked, the name is a plant's, or the choice's owner
      *)
  | Free of string  (** a new 4g plant of that (trimmed) name *)
  | Linked of {name : string; taxon : Herbier_refs.Sources.Gbif.Taxon.t}
      (** a new plant named [name], linked to [taxon] ([App.create_linked]) *)
  | To_identify  (** no name: « À identifier » *)

val target :
  plants:Plant.t list ->
  chosen:Plant.t option ->
  ?choice:Identify.Choice.t ->
  string ->
  target
(** With [choice = Some c] (6e), the text and [chosen] are ignored:
    {!Identify.Choice.owner} [~plants c] = [Some p] → [Existing p]; else
    {!Identify.Choice.taxon} [c] = [Some t] →
    [Linked {name = Choice.new_name c.proposal; taxon = t}]; else
    {!Identify.Choice.new_name} [c.proposal] as if typed (a plant of [plants]
    with that name or alias, else [Free]).

    Without [choice]: [chosen] (a tapped suggestion whose name is still the
    field's text) wins; else a plant of [plants] (the caller passes the live
    ones) whose display name or an alias equals the trimmed text, folding ASCII
    case only (« érable » is not « Érable »); else [Free], or [To_identify] when
    blank. *)

val choice_owner : plants:Plant.t list -> Identify.Choice.t -> Plant.t option
(** The plant of mine a save with this choice goes to: [Some p] when {!target}
    gives [Existing p], else [None]. What 6e's card names and says « Déjà dans
    ma collection » for. *)

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

(** {1 6a: the Identifier button} *)

val identify_label : string
(** ["Identifier avec Pl@ntNet"] *)

val identify_enabled : Identify_settings.gate -> photos:int -> bool
(** [Ready _] and [photos > 0]. *)

val identify_aria : Identify_settings.gate -> string
(** The button's aria-label: [Offline] →
    ["Identifier avec Pl@ntNet, indisponible hors-ligne"]; [No_key] →
    ["Identifier avec Pl@ntNet, clé API manquante"]; else {!identify_label}. *)

val offline_line : string
(** ["Hors-ligne : l'identification reviendra avec le réseau. Sans nom, la
     plante part dans « À identifier »."] *)

val identify_line : Identify_settings.gate -> string option
(** The 12 px line under the field: [No_key] →
    [Some Identify_settings.no_key_line] (precedence over offline, as
    {!Identify_settings.gate} already gives [No_key] offline); [Offline] →
    [Some offline_line]; [Ready _], [Waiting] → [None]. *)

val auto_open :
  armed:bool ->
  on_photo:bool ->
  Identify_settings.gate ->
  before:int ->
  added:int ->
  bool
(** Whether photos just added open 6b at once: [armed] (once per session;
    re-armed by [after.retake]), [before = 0] (they are the row's first),
    [added > 0], and {!Identify_settings.opens_on_photo} [~on_photo gate]. *)

(** {1 Kept answers (« Continuer sans attendre » then Identifier)} *)

type 'photo ask = {
  photos : 'photo list;
      (** the photos sent, in order (at most {!Organ.max_photos}) *)
  organs : Organ.sent list;
  flora : string;
      (** the flora id sent ([Plantnet.asked_flora] already applied by the
          caller) *)
  no_reject : bool;
}

val reuses : ('photo -> 'photo -> bool) -> kept:'photo ask -> 'photo ask -> bool
(** Whether the answer to [kept] stands for [ask], with no new request: same
    length and pairwise-equal photos (with the given equality: 4d passes
    physical equality of the preview Blobs), [List.equal Organ.equal_sent]
    organs, equal [flora], and [kept.no_reject || not ask.no_reject] (a forced
    answer also answers the ordinary ask; an ordinary one does not answer a
    forced ask). *)

val keep_answer :
  (Herbier_identify.identified, Identify.Failure.error) result -> bool
(** Whether an answer is kept for a reopen with the same ask: [Ok _] → [true];
    [Error (Plantnet No_plant)] → [true] (the same photos would get the same 404
    and spend a credit); every other error → [false]: notably
    [Plantnet Key_not_exposed] (the key may be exposed meanwhile),
    [Unreachable _], [Refused_request _], [Malformed _], [Quota_used_up],
    [Key_refused], [No_key], [No_photo], [Not_sent_offline],
    [Preview_unreadable]. *)

(** {1 6e: the choice card} *)

val choice_score : Plantnet.proposal -> string
(** ["Pl@ntNet " ^ Identify.Text.percent p.score]: 0.82 → ["Pl@ntNet 82 %"].
    Shown after the Latin name ([p.name], in italics) and [" · "]. *)

val already_line : Plant.t -> string
(** ["Déjà dans ma collection : l'observation s'ajoutera à <display_name>."] *)

val clear_choice_label : string
(** ✕'s aria-label: ["Effacer le choix"]. *)

(** {1 « + <organe> » from the layer: 4d's viewfinder} *)

val taking_label : Organ.sent -> string
(** The pill over the viewfinder while a photo is taken for the layer: [Given o]
    → ["Pl@ntNet · " ^ Organ.suggestion_label (Add o)] (« Pl@ntNet · + feuille
    »); [Auto] → ["Pl@ntNet · + photo"]. *)

val taking_cancel : string
(** ["Annuler"] *)

(** {1 What the layer's outcome does to 4d} *)

type choice_change =
  | Keep_choice
  | Clear_choice
  | Set_choice of Plantnet.proposal

val equal_choice_change : choice_change -> choice_change -> bool

type after = {
  choice : choice_change;
  clear_text : bool;  (** empty the name field's text *)
  retake : bool;
      (** drop the photos the layer sent from the row, and re-arm: the next
          first photo opens 6b again *)
}

val equal_after : after -> after -> bool

val after_layer : Identify.Layer.outcome -> after
(** - [Left] → keep everything ([Keep_choice], no clear, no retake);
    - [Chosen p] → [Set_choice p], [clear_text = true];
    - [None_matches] → [Clear_choice], text kept (a name typed before is the
      user's);
    - [Keep_unnamed] → [Clear_choice], [clear_text = true];
    - [Retake] → [Clear_choice], [clear_text = false], [retake = true]. *)
