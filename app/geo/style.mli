(** The map style: the pinned OpenFreeMap positron ([web/map/positron.json],
    served at {!path}) plus Herbier's overlay sources and layers. Pure. *)

type colours = {
  point : string;  (** an observation: [--map-point] *)
  point_border : string;  (** the ring around every point *)
  selected : string;  (** the selected cluster *)
  selected_halo : string;  (** the halo around it *)
  to_identify : string;  (** an "À identifier" observation *)
  accuracy_fill : string;  (** the GPS accuracy circle *)
  accuracy_line : string;  (** its border *)
}
(** CSS colour strings (handoff 4b, 4h), as {!Herbier_ui.Theme} reads them (it
    re-exports this type); MapLibre accepts them as they are. *)

val path : string
(** ["map/positron.json"], relative to [index.html]. *)

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

type error =
  | Not_a_style of string
      (** The base is not a JSON object with a ["sources"] object and a
          ["layers"] array; carries the missing or mistyped key (["sources"],
          ["layers"]) or ["root"]. *)
  | Duplicate_id of string
      (** An overlay source or layer id is already in the base. *)

val error_to_string : error -> string

val with_overlays : colours -> Yojson.Safe.t -> (Yojson.Safe.t, error) result
(** [with_overlays colours base]: [base] with, appended to ["sources"],
    {!observations_source} and {!accuracy_source}, each
    [{"type":"geojson","data":Features.empty}] (no clustering), and, appended
    after the base layers in this order:
    - {!accuracy_fill_layer}: a [fill] layer of {!accuracy_source}, [fill-color]
      [accuracy_fill];
    - {!accuracy_line_layer}: a [line] layer of {!accuracy_source}, [line-color]
      [accuracy_line], [line-width] 1;
    - {!points_layer}: a [circle] layer of {!observations_source},
      [circle-radius] 6, [circle-stroke-width] 3, [circle-stroke-color]
      [point_border], [circle-color]
      [["match",["get",Features.kind_key],"to_identify",to_identify,point]] (18
      px overall: handoff 4b).

    Every other key and every base layer and source is kept unchanged and in
    order. [selected] and [selected_halo] are not used. Never raises. *)
