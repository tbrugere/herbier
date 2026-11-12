(** Where a point's name comes from (architecture §8): the user's own labelled
    places first, with no network, then each place-name source the user turned
    on in 4m, all off by default. Pure: the online part is a {!Geocode.program}
    run by [Geocoder.run]. No Brr. Nothing here raises. *)

module Places := Herbier_domain.Places
module Observation := Herbier_domain.Observation

type source =
  | Ign_online
  | Photon_online
      (** « IGN en ligne » (Géoplateforme reverse, France box only) and « Photon
          en ligne » (komoot). *)

val equal_source : source -> source -> bool

val order : source list
(** [[Ign_online; Photon_online]]: the order sources are asked in, and the order
    of 4m's switches. *)

val label : source -> string
(** ["IGN en ligne"], ["Photon en ligne"]. *)

val detail : source -> string
(** What is sent to whom: 4m's detail line, and the first-opening notice's:
    - [Ign_online]: ["Envoie la position à l’IGN (data.geopf.fr), en France."]
    - [Photon_online]:
      ["Envoie la position à komoot (photon.komoot.io), et la recherche «
       Chercher un lieu »."] *)

type sources = {ign_online : bool; photon_online : bool}

val none : sources
(** Both [false]: the default of a fresh install and of an unreadable setting.
*)

val equal_sources : sources -> sources -> bool
val enabled : sources -> source -> bool

val set : sources -> source -> bool -> sources
(** [enabled (set s src b) src = b]; other fields unchanged. *)

val any_online : sources -> bool
(** Some online source is on. *)

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
  | Named of string  (** the [place_derived] to store *)
  | Unknown
      (** no own place and every enabled source answered without a name (or none
          is enabled): nothing stored, the screens say « Lieu inconnu » *)
  | Deferred
      (** no own place, some online source enabled, but [online = false]: no
          request; ask again when the phone is back online *)

val equal_outcome : outcome -> outcome -> bool

val outcome_to_string : outcome -> string
(** For logs: ["named <s>"], ["unknown"], ["deferred"]. *)

val resolve :
  sources:sources ->
  online:bool ->
  labelled:Observation.t list ->
  Places.point ->
  (outcome, Geocode.error) result Geocode.program
(** The name of [p]:
    - non-finite [lat] or [lon] → [Done (Ok Unknown)], no request;
    - [own labelled p = Some s] → [Done (Ok (Named s))], no request, whatever
      [sources] and [online];
    - else no source enabled → [Done (Ok Unknown)];
    - else [online = false] → [Done (Ok Deferred)];
    - else the enabled sources in {!order}, chained with [Geocode.or_else]:
      [Ign_online] → [Geocode.reverse_ign p], [Photon_online] →
      [Geocode.reverse_photon p]; [Some s] → [Named s]; all [None] → [Unknown];
      a decode error → [Done (Error e)] at once (no later source).

    Invariant: every [Get] issued has provider [Geoplateforme] only if
    [sources.ign_online], [Photon] only if [sources.photon_online], and no [Get]
    at all when [online = false]. *)
