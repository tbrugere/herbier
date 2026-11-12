(** Binding to the MapLibre facade [web/js/map.js] ([globalThis.herbier.map]).
    JSON (styles, GeoJSON) crosses as text; no domain types.

    Callbacks: a callback argument whose coordinates or zoom are missing or not
    finite numbers is dropped (the callback is not called); a non-string id is
    left out of {!click.ids}. A callback must not raise: it runs inside a
    MapLibre event handler, where an exception is uncaught.

    Every function but {!create} catches what the facade throws (a MapLibre
    error, invalid JSON text) and logs it with [Console.error] instead of
    raising: a map glitch is not a bug of ours. *)

type t
(** A facade handle (one MapLibre map). *)

type lng_lat = {lng : float; lat : float}
type camera = {center : lng_lat; zoom : float}

type click = {at : lng_lat; ids : string list; properties : string list}
(** [properties]: [JSON.stringify] of each hit feature's [properties] object, in
    hit order (topmost first, or nearest first for a near miss: see
    {!on_click}), one per feature, not deduplicated; a feature without a
    properties object gives ["{}"]. A non-string element is dropped. *)

val create :
  Brr.El.t ->
  style:string ->
  center:lng_lat ->
  zoom:float ->
  interactive:bool ->
  (t, Cap_error.t) result
(** [Error (Unavailable "map")] when [globalThis.herbier.map] is missing;
    [Error (Rejected _)] when the facade throws (no WebGL2, unparsable style).
    Never raises. *)

val set_style : t -> string -> unit
(** Replaces the whole style (JSON text); the last data given to each source
    with {!set_data} is applied again once the new style is loaded. *)

val set_data : t -> source:string -> string -> unit
(** Sets the GeoJSON (JSON text) of a [geojson] source of the style, now or, if
    the source does not exist yet, on the next style load. *)

val on_click : t -> layers:string list -> (click -> unit) -> unit
(** On every map click: where, and the [properties.id] strings of the features
    of [layers] under it, topmost first, without duplicates; [[]] when none. A
    finger is wider than a point: when no feature is under the click itself, the
    point features whose centre is within 22 CSS px (a 44 px target) are taken
    instead, nearest first. Layers absent from the style are ignored. *)

val on_moveend : t -> (camera -> unit) -> unit

val on_idle : t -> (unit -> unit) -> unit
(** MapLibre's [idle] events: no camera move running, every tile in view loaded
    and rendered. *)

val on_error : t -> (string -> unit) -> unit
(** MapLibre's [error] events (a tile or style request that failed), as their
    message. *)

val center : t -> lng_lat option
(** [None] if the facade throws or gives no finite centre. *)

val zoom : t -> float option
(** [None] if the facade throws or gives no finite zoom. *)

val fly_to : t -> center:lng_lat -> zoom:float -> unit

val fit_bounds :
  t ->
  west:float ->
  south:float ->
  east:float ->
  north:float ->
  padding:int ->
  max_zoom:float ->
  animate:bool ->
  unit
(** Frames the box with [padding] CSS pixels on every side, zooming in no
    further than [max_zoom]; [animate:false] jumps there without a transition
    (MapLibre still fires [moveend]). *)

val rendered_ids : t -> layers:string list -> string list
(** Distinct string [properties.id] of the features of [layers] currently
    rendered (in view); [[]] on failure. *)

val resize : t -> unit

val remove : t -> unit
(** Frees the map and its WebGL context; [t] is unusable afterwards. *)
