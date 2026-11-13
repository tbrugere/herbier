(** Global UI state shared by several screens (handoff « État », Global):
    filters common to Collection, Carte and Journal, network status, account.
    Per-screen state lives in each screen.

    One value of {!t} is created at startup and passed to the screens. Setters
    are called from outside an update step (a DOM callback, a resolved future),
    never from a binding. *)

module Tag_id := Herbier_domain.Ids.Tag_id

type filters = {
  tags : Tag_id.t list;  (** a plant must have all of them; [[]] = « Toutes » *)
  year : int option;  (** Journal's year chip; [None] = every year *)
  to_identify_only : bool;  (** Journal's « À identifier · n » chip *)
}

val no_filters : filters
val equal_filters : filters -> filters -> bool

type network = {online : bool; pending_uploads : int}

type account = {
  auth : Herbier_sync.Auth.status;  (** the Google account 4m shows *)
  storage : Herbier_domain.Photo.Original_target.t;
      (** the Settings choice, kept while signed out: Drive asks for the sign-in
          at the first photo to upload *)
  wifi_only : bool;  (** the Settings « Envoyer seulement en Wi-Fi » *)
}

type camera = {center : Herbier_domain.Places.point; zoom : float}

val equal_camera : camera -> camera -> bool
(** [Places.equal_point] on the centres and [Float.equal] on the zooms. *)

type map_view = {
  camera : camera option;  (** [None] until 4b has been shown once *)
  selected : Herbier_domain.Ids.Observation_id.t option;
      (** a place key ({!Herbier_geo.Features.place}) *)
  focus : Herbier_geo.Features.bounds option;
      (** a framing another screen asked for (4c « ◎ », 4h's mini-map): 4b
          frames it once, without animation, when its map exists, then sets it
          back to [None] *)
}
(** 4b's camera and selected place, kept across tab switches and modals (handoff
    « État », Carte: viewport, selectedCluster), and a one-shot framing asked by
    another screen. *)

val no_map_view : map_view
(** All three [None]. *)

type t

val create :
  network:network ->
  account:account ->
  place_sources:Herbier_geo.Place_name.sources ->
  t
(** Filters start empty; [network], [account] and [place_sources] are what the
    platform and the settings say at startup. *)

val filters : t -> filters React.signal
val network : t -> network React.signal
val account : t -> account React.signal
val map_view : t -> map_view React.signal

val place_sources : t -> Herbier_geo.Place_name.sources React.signal
(** The 4m « Noms de lieux » switches; [eq] = [Place_name.equal_sources].
    Written through [App.set_place_source]. *)

val set_filters : t -> ?step:React.step -> filters -> unit
(** [step] groups this change with other setters in one update step (style guide
    9.3); without it the setter runs its own step. *)

val set_network : t -> ?step:React.step -> network -> unit
val set_account : t -> ?step:React.step -> account -> unit
val set_map_view : t -> ?step:React.step -> map_view -> unit

val set_place_sources :
  t -> ?step:React.step -> Herbier_geo.Place_name.sources -> unit

val focus_map : t -> Herbier_geo.Features.bounds -> unit
(** Asks 4b to frame the bounds at its next showing: the camera unchanged,
    [selected = None], [focus = Some b], in one update step. Called from a DOM
    handler, right before [Route.go (Tab Map)]. *)
