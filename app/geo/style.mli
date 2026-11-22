(** The map style: the pinned OpenFreeMap liberty ([web/map/liberty.json],
    served at {!path}) plus Herbier's overlay sources and layers. Pure. *)

type colours = {
  point : string;  (** an observation: [--map-point] *)
  point_border : string;  (** the ring around every point *)
  selected : string;  (** the selected cluster *)
  selected_halo : string;  (** the halo around it *)
  to_identify : string;  (** an "À identifier" observation *)
  accuracy_fill : string;  (** the GPS accuracy circle *)
  accuracy_line : string;  (** its border *)
  origin : string;  (** 5b's origin ghost: [--map-origin] *)
}
(** CSS colour strings (handoff 4b, 4h), as {!Herbier_ui.Theme} reads them (it
    re-exports this type); MapLibre accepts them as they are. *)

val path : string
(** ["map/liberty.json"], relative to [index.html]. *)

(** {1 Dev page only}

    The [#dev/map] check ([app/ui/dev/map_check.ml]) draws raw observations and
    the accuracy circle with these; 4b draws {!members_layer} instead. In every
    style they cost an empty source and layers with nothing to paint. *)

val observations_source : string
(** ["herbier-observations"] *)

val accuracy_source : string
(** ["herbier-accuracy"] *)

val points_layer : string
(** ["herbier-points"] *)

val accuracy_fill_layer : string
(** ["herbier-accuracy-fill"] *)

val accuracy_line_layer : string
(** ["herbier-accuracy-line"] *)

(** {1 Places (handoff 4b)} *)

val detail_zoom : float
(** [15.]: places below, observations from here (handoff 4b; 500 m is about 150
    px at 45°N). *)

val places_source : string
(** ["herbier-places"]: one point per place, clustered by MapLibre. *)

val members_source : string
(** ["herbier-members"]: the shown observations of every place. *)

val selection_source : string
(** ["herbier-selection"]: {!Features.selection}. *)

val groups_layer : string
(** ["herbier-groups"] *)

val groups_count_layer : string
(** ["herbier-groups-count"] *)

val places_layer : string
(** ["herbier-places"] (layers and sources are separate namespaces) *)

val members_layer : string
(** ["herbier-members"] *)

val selection_halo_layer : string
(** ["herbier-selection-halo"] *)

val selection_place_layer : string
(** ["herbier-selection-place"] *)

val selection_members_layer : string
(** ["herbier-selection-members"] *)

(** {1 Observation (handoff 4h, 5b)} *)

val focus_source : string
(** ["herbier-focus"]: 4h's point ({!Features.focus}). *)

val focus_layer : string
(** ["herbier-focus"] *)

val origin_source : string
(** ["herbier-origin"]: 5b's origin ghost ({!Features.focus} of the stored
    position). *)

val origin_layer : string
(** ["herbier-origin"] *)

type error =
  | Not_a_style of string
      (** The base is not a JSON object with a ["sources"] object and a
          ["layers"] array; carries the missing or mistyped key (["sources"],
          ["layers"]) or ["root"]. *)
  | Duplicate_id of string
      (** An overlay source or layer id is already in the base. *)

val error_to_string : error -> string

val with_overlays : colours -> Yojson.Safe.t -> (Yojson.Safe.t, error) result
(** [with_overlays colours base]: [base] with, appended to ["sources"] in this
    order:
    - {!observations_source} and {!accuracy_source}, each
      [{"type":"geojson","data":Features.empty}] (no clustering);
    - {!places_source}: the same with ["cluster": true], ["clusterRadius"] 40,
      ["clusterMaxZoom"] [detail_zoom - 1] and ["clusterProperties"] summing
      [count] and [identified] and taking the min of [west], [south] and the max
      of [east], [north] ({!Features.place_points});
    - {!members_source}, {!selection_source}, {!origin_source} and
      {!focus_source}: unclustered.

    and, appended after the base layers in this order:
    - {!accuracy_fill_layer}: a [fill] layer of {!accuracy_source}, [fill-color]
      [accuracy_fill];
    - {!accuracy_line_layer}: a [line] layer of {!accuracy_source}, [line-color]
      [accuracy_line], [line-width] 1;
    - {!points_layer}: a [circle] layer of {!observations_source},
      [circle-radius] 6, [circle-stroke-width] 3, [circle-stroke-color]
      [point_border], [circle-color]
      [["match",["get",Features.kind_key],"to_identify",to_identify,point]] (18
      px overall: handoff 4b);
    - below {!detail_zoom} ([maxzoom]), on {!places_source}: {!groups_layer}
      (MapLibre clusters, radius 9) and {!groups_count_layer} (their summed
      [count], Noto Sans Bold 11 in [point_border]), then {!places_layer} (the
      unclustered places, radius 6); the colour is [to_identify] when
      [identified] is 0, else [point]; ring 3 px [point_border];
    - from {!detail_zoom} ([minzoom]): {!members_layer}, painted as
      {!points_layer};
    - on {!selection_source}: {!selection_halo_layer} (radius 28,
      [selected_halo], 2 px [selected] border) and {!selection_place_layer}
      (radius 7, [selected]) for the ["role"] ["place"] feature below
      {!detail_zoom}; {!selection_members_layer} (radius 7, [selected]) for the
      ["member"] features from {!detail_zoom};
    - {!origin_layer}: a [circle] layer of {!origin_source} at every zoom,
      radius 6, [origin], 3 px [point_border] ring, [circle-opacity] and
      [circle-stroke-opacity] 0.7 (18 px overall: handoff 5b's grey ghost);
    - last, {!focus_layer}: a [circle] layer of {!focus_source} at every zoom,
      radius 7, [selected], 3 px [point_border] ring (20 px overall, as 4b's
      selected point), above the accuracy circle.

    Every other key and every base layer and source is kept unchanged and in
    order. [Duplicate_id] when a new source id is already a base source or a new
    layer id already a base layer. Never raises. *)
