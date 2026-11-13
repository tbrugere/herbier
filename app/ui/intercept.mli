(** 4j « Lien intercepté » without network, timers or DOM: the text that
    arrived, the sheet's state (resolution, offline, fallback to 4i), the card's
    texts, the recent tags and the first observation. Pure; never raises. *)

module Link := Herbier_domain.Link
module Plant := Herbier_domain.Plant
module Tag := Herbier_domain.Tag
module Observation := Herbier_domain.Observation
module Candidate := Herbier_refs.Resolve.Candidate
module Taxon := Herbier_refs.Sources.Gbif.Taxon

(** {1 What arrived} *)

val cap : int
(** [4096]: the most bytes of a text that arrived that are kept, far above a
    link or a species name. *)

val of_url : string -> string option
(** [appUrlOpen]'s url, trimmed; [None] when blank. Capped as {!of_share} is. *)

val of_share : title:string -> texts:string list -> string option
(** The non-blank [texts], each trimmed, joined with ["\n"]; when there is none,
    the trimmed [title]; [None] when that is blank too. The title is never added
    to a non-blank text. A result longer than {!cap} bytes is cut to at most
    {!cap} bytes at a UTF-8 character boundary, then trimmed. *)

(** {1 The sheet} *)

val header : Link.t -> string
(** The header line after « Herbier · » (the CSS upper-cases it): [Gbif _] →
    ["lien GBIF reconnu"]; [Plantnet _ | Plantnet_observation _] →
    ["lien Pl@ntNet reconnu"]; [Plantuse _] → ["lien Pl@ntUse reconnu"];
    [Wikipedia _] → ["lien Wikipédia reconnu"]; [Inpn _] →
    ["lien INPN reconnu"]; [Tela _] → ["lien Tela Botanica reconnu"]; [Powo _] →
    ["lien POWO reconnu"]; [Inat _] → ["lien iNaturalist reconnu"]; [Text _] →
    ["partage reçu"]. *)

val query : Link.t -> string
(** What 4i is prefilled with for this link, as
    {!Herbier_refs.Resolve.outcome}'s [query]: [Plantnet n], [Plantuse n] → [n];
    [Wikipedia {title; _}] → [title]; [Text s] → [String.trim s]; every other
    constructor → [""]. *)

type status =
  | Offline  (** No network: « Hors-ligne … » + « Chercher ». *)
  | Resolving
      (** Link lookup or names in flight: « Recherche de l'espèce… ». *)
  | Failed of string
      (** A call failed (network, status or body): « La recherche de l'espèce a
          échoué. » + « Réessayer » + « Chercher »; the message is for the
          console. *)
  | Found of {candidate : Candidate.t; existing : Plant.t option}
      (** The card. [existing = Some p]: « Déjà dans ma collection ». *)
  | Search of string
      (** Leave for 4i prefilled with this text: free text, an observation link,
          no species. *)

val equal_status : status -> status -> bool
(** Structural; [existing] compared by plant id and [updated_at]. *)

type t

val link : t -> Link.t
val status : t -> status
val seq : t -> int

type effect_ =
  | No_effect
  | Resolve of {seq : int}
      (** [Resolver.resolve (link t)], then {!resolved} [~seq]. *)
  | Name of {seq : int; taxon : Taxon.t}
      (** [Resolver.named taxon], then {!named} [~seq]. *)

val init : online:bool -> plants:Plant.t list -> string -> t * effect_
(** [init ~online ~plants text]: [link] is [Link.classify text]; [seq = 0]. The
    words around the link, [Link.without_urls text], prefill 4i wherever the
    link itself gives an empty query (below: "the prefill"). [Text _] → [Search]
    the words around ([""] for a lone URL no pattern matches), [No_effect],
    online or not. [Plantnet_observation _] → [Search] the words around,
    [No_effect]. Any other link: online → [Resolving], [Resolve {seq = 0}];
    offline → [Offline], [No_effect]. [plants] (the live plants, any order) are
    kept for {!named}. *)

val resolved : seq:int -> Herbier_refs.Resolve.outcome -> t -> t * effect_
(** A stale [seq], or a status other than [Resolving] → unchanged, [No_effect].
    Otherwise: [Taxon x] → [Resolving] (same seq), [Name {seq; taxon = x}];
    [Candidates _] → [Search (query (link t))], or the words around the link
    when that is [""], [No_effect];
    [Unresolved {query = q; why = No_species | Observation_link}] → [Search q],
    or the words around the link when [q = ""];
    [Unresolved {why = Unavailable m; _}] → [Failed m], [No_effect]. *)

val named : seq:int -> Candidate.t -> t -> t
(** Stale [seq] or status not [Resolving] → unchanged. Otherwise
    [Found {candidate; existing}] with [existing] = [Some p] when
    [Ref_pick.action Browse ~current:None ~plants candidate.taxon] is [Open p]
    (a live plant with that gbif_key, or with the taxon's accepted key), [None]
    otherwise. *)

val network : online:bool -> t -> t * effect_
(** Offline while [Resolving] or [Failed _] → [seq + 1] (late answers dropped),
    [Offline], [No_effect]. Online while [Offline] → [seq + 1], [Resolving],
    [Resolve {seq}]. Anything else unchanged, [No_effect] ([Found] and [Search]
    stay). *)

val retry : online:bool -> t -> t * effect_
(** « Réessayer », status [Failed _] only: online → [seq + 1], [Resolving],
    [Resolve {seq}]; offline → [Offline], [No_effect]. Other status → unchanged,
    [No_effect]. *)

val search_query : t -> string
(** « Pas la bonne espèce ? Chercher »: [Found] → [Taxon.latin] of its taxon;
    [Search q] → [q]; otherwise [query (link t)], or the words around the link
    when that is [""]. *)

(** {1 The card} *)

val name : Candidate.t -> existing:Plant.t option -> string
(** [existing]'s [display_name]; else {!Plant_link.display_name} (first French
    name, else canonical, else scientific name). *)

val meta : Taxon.t -> string
(** [family ^ " · GBIF"], or ["GBIF"] without a family:
    ["Plantaginaceae · GBIF"]. *)

val place_line : Gps.t -> string
(** « Première observation ici »'s second line: [Searching] →
    ["Position… · maintenant"]; [Fix p] →
    [Printf.sprintf "%.4f, %.4f · maintenant" p.lat p.lon]
    (["48.0331, 7.0028 · maintenant"]); [No_fix] →
    ["Sans position · maintenant"]. *)

val recent_count : int
(** [6] *)

val session_s : float
(** [43_200.] (12 h) *)

val recent_tags :
  now:Ptime.t ->
  tags:Tag.t list ->
  links:Tag.Plant_tag.t list ->
  except:Herbier_domain.Ids.Tag_id.t list ->
  (Tag.t * bool) list
(** The tags card: the live [tags] (deleted ones ignored) not in [except] that
    have at least one live link in [links], ordered by their newest live link's
    [created_at], newest first (ties: [name] by [String.compare], then id), at
    most {!recent_count}. The flag (preselected) is true when that newest link
    is at most {!session_s} before [now] (a link dated after [now] counts as
    recent). A tag with no live link is never listed. [except] is the existing
    plant's tags in the « Déjà dans ma collection » variant, [[]] otherwise. *)

val observation :
  id:Herbier_domain.Ids.Observation_id.t ->
  at:Ptime.t ->
  plant:Herbier_domain.Ids.Plant_id.t ->
  Gps.t ->
  Observation.t
(** « Première observation ici »: [plant_id = Some plant],
    [at = created_at = updated_at = at], [position] = [Some p] for [Fix p],
    [None] for [Searching] and [No_fix]; [place_label], [place_derived], [note],
    [deleted_at] all [None]. *)
