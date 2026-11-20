(** 4h's mini-map: a non-interactive MapLibre map ({!Herbier_geo_io.Map},
    [interactive:false]) 130 px high showing a position as a moss point
    ({!Herbier_geo_io.Map.set_focus}) and, when its accuracy is known, the
    metric accuracy circle ({!Herbier_geo_io.Map.set_accuracy}); the only place
    the accuracy shows (handoff 4h). Taps are reported, not acted on.

    The map is created once, at the first position with finite coordinates (an
    observation without position gets no WebGL context), and kept while the
    position changes: each change moves the point and the circle and frames the
    circle's box ({!Herbier_geo.Features.accuracy_bounds}, 16 px padding, max
    zoom 17) without animation; a change arriving while the map is being created
    is applied when it is ready, the latest one winning. [el] must be in the
    document by the time the style fetch resolves. A creation failure is logged
    with [Console.error] and hides [el] for good. Releasing the bindings removes
    the map, also when its creation resolves afterwards. Never raises. *)

type t = {
  el : Brr.El.t;
      (** [div.mini-map] holding the map and, over its canvas but under
          MapLibre's controls (the attribution), the tap target
          [button.mini-map__tap] with
          [aria-label="Corriger la position sur la carte"]
          ({!Herbier_ui_model.Observation_plan.map_label}: 4h opens 5b); class
          [is-hidden] while the position is [None] (or has a non-finite
          coordinate), and for good once the map failed *)
  tap : unit React.event;
      (** a click on the tap target (Enter / Space included, as on any button);
          the attribution's toggle and links are not part of it *)
  bindings : Rb.binding list;
}

val v :
  colours:Herbier_geo.Style.colours ->
  Herbier_domain.Observation.position option React.signal ->
  t
