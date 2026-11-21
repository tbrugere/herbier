(** Where a point's name comes from (architecture §8): the user's own labelled
    places first, with no network, then each place-name source the user turned
    on in 4m, all off by default: « IGN hors-ligne » from the downloaded commune
    packs ({!Communes}), then the online ones. Pure: the online part is a
    {!Geocode.program} run by [Geocoder.run]. No Brr. Nothing here raises. *)

module Places := Herbier_domain.Places
module Observation := Herbier_domain.Observation

type source =
  | Ign_offline
  | Ign_online
  | Photon_online
      (** « IGN hors-ligne » (the downloaded commune packs, no request), « IGN
          en ligne » (Géoplateforme reverse, France box only) and « Photon en
          ligne » (komoot). *)

val equal_source : source -> source -> bool

val order : source list
(** [[Ign_offline; Ign_online; Photon_online]]: the order sources are asked in,
    and the order of 4m's switches. *)

val label : source -> string
(** ["IGN hors-ligne"], ["IGN en ligne"], ["Photon en ligne"]. *)

val detail : source -> string
(** What is sent to whom: 4m's detail line, and the first-opening notice's:
    - [Ign_offline]:
      ["N’envoie aucune position ; nomme d’après les communes des départements
       téléchargés (IGN, data.geopf.fr)."]
    - [Ign_online]: ["Envoie la position à l’IGN (data.geopf.fr), en France."]
    - [Photon_online]:
      ["Envoie la position à komoot (photon.komoot.io), et la recherche «
       Chercher un lieu »."]

    No inner colon and nothing pointing elsewhere on the page: the notice prints
    ["<label> : <detail>"]. *)

val notice_line : source -> string
(** ["<label> : <detail>"]: an item of the first-opening notice's list. *)

type sources = {ign_offline : bool; ign_online : bool; photon_online : bool}

val none : sources
(** All [false]: the default of a fresh install and of an unreadable setting. *)

val equal_sources : sources -> sources -> bool
val enabled : sources -> source -> bool

val set : sources -> source -> bool -> sources
(** [enabled (set s src b) src = b]; other fields unchanged. *)

val is_online : source -> bool
(** Whether the source sends the position: [false] for [Ign_offline] only. *)

val any_online : sources -> bool
(** Some enabled source {!is_online}: [ign_online || photon_online]. *)

val any_enabled : sources -> bool
(** Some source is on, offline or online. *)

val offline_only : sources -> sources
(** [s] with every {!is_online} source off
    ([{none with ign_offline = s.ign_offline}]): what App asks for a point
    already tried remotely this session (local lookups stay free). *)

val can_search : sources -> bool
(** [photon_online]: 5b « Chercher un lieu » may send its query (and the map
    centre) to Photon. *)

val allows : sources -> Geocode.provider -> bool
(** Whether a request to that provider may leave: [Geoplateforme] with
    [ign_online], [Photon] with [photon_online]. The [allow] that callers of
    [Geocoder.run] read again when a request leaves the queue. *)

val own : Observation.t list -> Places.point -> string option
(** The user's own place for [p]: among the given observations that are live
    ([deleted_at = None]), have a position with finite [lat]/[lon]
    ([Places.position_point]) and a [place_label] that is non-blank after
    [String.trim], those [Places.within] [p]; the nearest by
    [Places.distance_m], ties broken by [Places.compare_obs] (earliest [at],
    then id). Its trimmed label, verbatim (no « Près de »). [None] when none
    qualifies or [p] has a non-finite coordinate. *)

type outcome =
  | Named of Geocode.named
      (** the [place_derived] to store, with its optional [place_detail] *)
  | Unknown
      (** no own place and every enabled source answered without a name (or none
          is enabled): nothing stored, the screens say « Lieu inconnu » *)
  | Deferred
      (** no own place, some online source enabled, but [online = false]: no
          request; ask again when the phone is back online *)

val equal_outcome : outcome -> outcome -> bool

val outcome_to_string : outcome -> string
(** For logs and the dev page: ["named <Geocode.named_to_string n>"],
    ["unknown"], ["deferred"]. *)

val resolve :
  sources:sources ->
  online:bool ->
  labelled:Observation.t list ->
  communes:Communes.t ->
  Places.point ->
  (outcome, Geocode.error) result Geocode.program
(** The name of [p]:
    - non-finite [lat] or [lon] → [Done (Ok Unknown)], no request;
    - [own labelled p = Some s] → [Done (Ok (Named {name = s; detail = None}))],
      no request, whatever [sources] and [online] (a user's label never gets a
      detail);
    - else [sources.ign_offline] and [Communes.name communes p = Some s] →
      [Done (Ok (Named {name = s; detail = None}))], no request, whatever
      [online] (the packs hold communes only, no lieu-dit);
    - else no online source enabled → [Done (Ok Unknown)];
    - else [online = false] → [Done (Ok Deferred)];
    - else the enabled online sources in {!order}, chained with
      [Geocode.or_else]: [Ign_online] → [Geocode.reverse_ign p], [Photon_online]
      → [Geocode.reverse_photon p], each commune first with its own detail;
      [Some n] → [Named n]; all [None] → [Unknown]; a decode error →
      [Done (Error e)] at once (no later source).

    [communes] is ignored when [ign_offline] is off. Invariant: every [Get]
    issued has provider [Geoplateforme] only if [sources.ign_online], [Photon]
    only if [sources.photon_online], and no [Get] at all when [online = false].
*)
