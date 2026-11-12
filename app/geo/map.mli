(** A MapLibre map over the facade (architecture §8): the pinned positron style
    with Herbier's overlays ({!Style}), the observations as points, the accuracy
    circle. *)

module Places = Herbier_domain.Places
module Observation = Herbier_domain.Observation
module Observation_id = Herbier_domain.Ids.Observation_id

type t

type error =
  | Style_fetch of string
      (** Fetching {!Style.path} failed: the HTTP status or the message. *)
  | Style_parse of string  (** Its text is not JSON (Yojson's message). *)
  | Style of Style.error
  | Map of Herbier_bindings.Cap_error.t
      (** {!Herbier_bindings.Maplibre.create} failed (no facade, no WebGL2). *)

val error_to_string : error -> string

val create :
  Brr.El.t ->
  colours:Style.colours ->
  center:Places.point ->
  zoom:float ->
  interactive:bool ->
  (t, error) result Fut.t
(** Fetches {!Style.path} (same origin), parses it, adds the overlays with
    {!Style.with_overlays}, then creates the map in the element, which must be
    in the document with a non-zero size. The future always resolves; never
    raises. *)

val set_observations : t -> Observation.t list -> unit
(** {!Features.observations} into {!Style.observations_source}. Used by the
    [#dev/map] page only (4b uses {!set_places}). *)

val set_accuracy : t -> (Places.point * float) option -> unit
(** [Some (centre, radius_m)]: {!Features.circle} with {!Features.circle_steps}
    steps into {!Style.accuracy_source}; [None]: {!Features.empty}. Used by the
    [#dev/map] page and 4h's mini-map. *)

val set_focus : t -> Places.point option -> unit
(** {!Features.focus} into {!Style.focus_source}. *)

val set_origin : t -> Places.point option -> unit
(** {!Features.focus} into {!Style.origin_source}: 5b's origin ghost. *)

val set_places : t -> Features.place list -> unit
(** {!Features.place_points} into {!Style.places_source} and
    {!Features.observations} of every place's [shown] into
    {!Style.members_source}. *)

val set_selection : t -> Features.place option -> unit
(** {!Features.selection} into {!Style.selection_source}. *)

type click = {at : Places.point; observations : Observation_id.t list}
(** The point tapped and the observations under it, topmost first (ids that do
    not parse are dropped). *)

val on_click : t -> (click -> unit) -> unit
(** Clicks on the map, hit-testing {!Style.points_layer}. The callback must not
    raise. Used by the [#dev/map] page only (4b uses {!on_tap}). *)

type tap = {at : Places.point; hits : Features.hit list}
(** In {!Herbier_bindings.Maplibre.on_click}'s order (topmost first, or nearest
    first for a near miss). *)

val on_tap : t -> (tap -> unit) -> unit
(** Clicks hit-testing {!Style.selection_members_layer},
    {!Style.selection_place_layer}, {!Style.members_layer},
    {!Style.places_layer} and {!Style.groups_layer}; the list does not set the
    priority, the style's paint order does. A feature whose properties do not
    decode ({!Features.hit}) is dropped with a [Console.warn] naming its keys; a
    tap whose features all fail to decode is not reported at all, so that it is
    not taken for a tap on empty map. The callback must not raise. *)

val on_moveend : t -> (center:Places.point -> zoom:float -> unit) -> unit
(** After every camera move. The callback must not raise. *)

val on_movestart : t -> (user:bool -> unit) -> unit
(** When a camera move starts; [user] when a gesture started it, [false] for
    {!fly_to}, {!fit} or a resize of the element. The callback must not raise. A
    {!on_moveend} follows every [movestart]. *)

val on_idle : t -> (unit -> unit) -> unit
(** Each time the map settles: no camera move running and every tile in view
    loaded and rendered. The callback must not raise. *)

val on_error : t -> (string -> unit) -> unit
(** MapLibre's errors (a tile or glyph request that failed), as text. *)

val center : t -> Places.point option
(** [None] when the facade fails or gives no finite centre. *)

val zoom : t -> float option
(** [None] when the facade fails or gives no finite zoom. *)

val fly_to : t -> center:Places.point -> zoom:float -> unit

val fit :
  ?max_zoom:float ->
  ?animate:bool ->
  t ->
  Features.bounds ->
  padding_px:int ->
  unit
(** Frames the bounds, with [padding_px] CSS pixels on every side, zooming in no
    further than [max_zoom] (default 16, so one point or a tight group keeps its
    surroundings in view). [animate] (default [true]): [false] jumps there
    without a transition. *)

val rendered : t -> Observation_id.t list
(** Observations whose point is currently rendered (in view). *)

val resize : t -> unit

val remove : t -> unit
(** Frees the map and its WebGL context; [t] is unusable afterwards. *)
