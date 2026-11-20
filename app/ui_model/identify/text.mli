(** Every French text of the identification layer (6b, 6c, 6d, 6f, 6g). Pure. No
    string here names CORS, an origin, localhost, exposing or the [api-key]
    parameter: the console line of a request names its error class. *)

val kicker : Caller.t -> string
(** [Observation], [Free_name _] → ["Pl@ntNet"]; [Queue (Some {index; total})] →
    ["À identifier · <index> / <total>"]; [Queue None] → ["À identifier"] (the
    CSS upper-cases it). *)

val title : string

val back_label : string
(** ← 's aria-label and 6g's button. *)

val sending : string

val not_kept : photos:int -> string
(** 1 → ["Pl@ntNet ne conserve pas la photo."]; more →
    ["Pl@ntNet ne conserve pas les photos."] *)

val skeleton_label : string
val continue_ : string

val proposals_label : Caller.t -> count:int option -> string
(** [count = None] (6b) → ["Propositions"]; [Some n] → ["Propositions · <n>"];
    [Queue _] → ["Propositions Pl@ntNet"] / ["Propositions Pl@ntNet · <n>"]. *)

val flora_label : Herbier_store.Settings.flora option -> string
(** {!Identify_settings.flora_detail} (« Automatique » for [None]). *)

val percent : float -> string
(** [Float.round (score *. 100.)] clamped to [0, 100], ["<p> %"] (plain space):
    0.82 → ["82 %"], 0.44239 → ["44 %"], 1.0 → ["100 %"]; a positive score that
    rounds to 0 → ["< 1 %"]; 0, negative or nan → ["0 %"]. *)

val bar_width : float -> string
(** The score bar's CSS width: score clamped to [0, 1] (nan → 0), ["<x>%"] with
    at most one decimal: 0.44239 → ["44.2%"], 1.5 → ["100%"], -1 → ["0%"]. *)

val common_names : Herbier_identify.Plantnet.proposal -> string option
(** [common_names] joined by [" · "]; [[]] → [None]. *)

val organ_badge : Herbier_identify.Organ.t option -> string
(** [Some o] → [Organ.label o ^ " ▾"] (« fleur ▾ »); [None] → ["organe ▾"]. *)

val tile_organ : Herbier_identify.Organ.t option -> string option
(** A species tile's band: [Some o] → [Some (Organ.label o)]; [None] → [None].
*)

val add_word : Herbier_identify.Organ.suggestion -> string
(** The word under the « + » of the add tile: [Add o] → [Organ.label o];
    [Add_photo] → ["photo"]. Its aria-label is
    {!Herbier_identify.Organ.suggestion_label}. *)

val add_hint : Herbier_identify.Organ.suggestion -> string
(** [Add Flower] → ["Une fleur en plus départage les espèces proches."];
    [Add Leaf] → ["Une feuille en plus …"]; [Add Fruit] →
    ["Un fruit en plus …"]; [Add Bark] → ["L'écorce en plus …"]; [Add Habit] →
    ["Le port en plus …"]; [Add_photo] →
    ["Une photo en plus départage les espèces proches."]. *)

val owned : Caller.t -> Owned.t -> string
(** [Observation], [Queue _] →
    ["Dans ma collection · <display_name> · <n> obs."]; [Free_name _] →
    {!Ref_pick.also_owned} (4i's Relink wording). *)

val action : Caller.action -> string
(** [Link] → ["Lier"]; [Create] → ["+ Créer"]. *)

val none_matches : string

val organ_menu_label : string
(** The organ menu's aria-label. *)

val flora_menu_label : string
val failure_title : Failure.t -> string

val failure_body : photos:int -> Failure.t -> string
(** [No_plant _] → ["Pas de plante détectée sur cette photo."] (photos > 1:
    ["… sur ces photos."]); [Not_answered] → ["Réessayez dans un moment."];
    [Offline] → ["Rien n'a été envoyé : réessayez avec le réseau."]; [Used_up] →
    ["Les <Plantnet.daily_quota> identifications Pl@ntNet du jour sont utilisées
     : réessayez demain."]; [Key_refused] →
    ["Pl@ntNet a refusé la clé : vérifiez-la dans Réglages."]; [No_key] →
    {!Identify_settings.no_key_line}; [Unreadable] →
    ["Une photo n'a pas pu être lue sur le téléphone : rien n'a été envoyé."].
*)

val retry : string
val force : string

val reask_blocked : Identify_settings.gate -> string option
(** Why the re-ask controls (organ menu, add tile, flora menu, « Voir quand même
    », « Réessayer ») are disabled: [Ready _] → [None]; [Offline] →
    [Some "Hors-ligne : rien ne peut être envoyé à Pl@ntNet."]; [No_key] →
    [Some Identify_settings.no_key_line]; [Waiting] → [None] (disabled, no
    line). *)

(** {1 6d Comparer} *)

val tile_label :
  Herbier_identify.Plantnet.proposal ->
  Herbier_identify.Plantnet.image ->
  more:int ->
  string
(** The aria-label of a species tile in 6c (a button opening 6d): [more <= 0] →
    ["Comparer : <name>, <organ label>"] (["Comparer : <name>"] when the image's
    organ is [None]); [more > 0] (the « +N » tile) →
    ["Comparer : <name>, <more> photos de plus"] (["1 photo de plus"] for 1).
    [<name>] is [p.name]. *)

val compare_close : string
(** ✕'s aria-label: ["Fermer la comparaison"]. *)

val compare_position : index:int -> count:int -> string
(** 1-based: ["Proposition <index> / <count>"]. *)

val compare_mine : Herbier_identify.Organ.t option -> string
(** ["Ma photo · fleur"]; [None] → ["Ma photo"]. *)

val compare_species : Herbier_identify.Organ.t option -> string
(** ["Pl@ntNet · fleur"]; [None] → ["Pl@ntNet"]. *)

val compare_image_position : index:int -> count:int -> string
(** 1-based: ["3 / 6"]. *)

val compare_names : Herbier_identify.Plantnet.proposal -> string option
(** The first French name and the family joined by [" · "]
    (["Rose de Chine · Malvaceae"]); either alone when the other is absent;
    [None] when both are. *)

val compare_owned : Caller.t -> Owned.t -> string
(** [Observation], [Queue _] → ["Dans ma collection · <display_name>"] (no
    observation count in 6d); [Free_name _] →
    ["Aussi dans ma collection : <display_name>"]. *)

val compare_action : Caller.action -> string
(** 6c's {!action}: [Link] → ["Lier"]; [Create] → ["+ Créer"]. *)

val compare_previous : string
(** ‹ 's aria-label: ["Proposition précédente"]. *)

val compare_next : string
(** › 's aria-label: ["Proposition suivante"]. *)

val compare_no_image : string
(** A proposal without images, reached by ‹ ›:
    ["Pl@ntNet n'a pas envoyé de photo de cette espèce."] *)
