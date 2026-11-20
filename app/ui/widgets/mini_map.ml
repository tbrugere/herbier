open Brr
module Observation = Herbier_domain.Observation
module Places = Herbier_domain.Places
module Features = Herbier_geo.Features
module Geo_map = Herbier_geo_io.Map

type t = {el : El.t; tap : unit React.event; bindings : Rb.binding list}

let creation_zoom = 16.
let padding_px = 16

(* The zoom follows the circle's box, capped at 17 so a small circle keeps its
   surroundings readable. *)
let max_zoom = 17.

let framing pos =
  Option.bind pos (fun p ->
      Option.map (fun b -> (p, b)) (Features.accuracy_bounds p))

(* style: the MapLibre handle (style guide 2.2): created asynchronously, and
   the widget may be released before it exists. *)
type map_state = Idle | Creating | Ready of Geo_map.t | Failed | Released

let show m ((p : Observation.position), bounds) =
  let point : Places.point = {lat = p.lat; lon = p.lon} in
  (* [el] is [display: none] while there is no position to show, and the map
     then measures 0x0: resize before framing. *)
  Geo_map.resize m;
  Geo_map.set_focus m (Some point);
  Geo_map.set_accuracy m (Option.map (fun r -> (point, r)) p.accuracy_m);
  Geo_map.fit m bounds ~padding_px ~max_zoom ~animate:false

let v ~colours position =
  let position =
    React.S.map ~eq:(Option.equal Observation.equal_position) Fun.id position
  in
  (* The tap target is a button laid over the canvas, not [el]: MapLibre fills
     [el] with its attribution (a toggle and links), which must stay outside
     any button and above it. *)
  let button =
    Html.button ~label:Herbier_ui_model.Observation_plan.map_label
      ["mini-map__tap"] []
  in
  let el = El.div ~at:[At.class' (Jstr.v "mini-map")] [button] in
  let tap, click = Rb.click button in
  let set_hidden hidden = El.set_class (Jstr.v "is-hidden") hidden el in
  (* style: written from the position binding, the creation's future and the
     release, never read by the graph. [latest] is what a map being created
     shows once ready. *)
  let map = ref Idle and latest = ref (framing (React.S.value position)) in
  let create ((p : Observation.position), _) =
    map := Creating;
    Fut.await
      (Geo_map.create el ~colours ~center:{lat = p.lat; lon = p.lon}
         ~zoom:creation_zoom ~interactive:false)
      (fun result ->
        match (!map, result) with
        | Released, Ok m -> Geo_map.remove m
        | Released, Error _ -> ()
        | (Idle | Creating | Ready _ | Failed), Error e ->
            map := Failed;
            Log.error "mini-carte" (Geo_map.error_to_string e);
            set_hidden true
        | (Idle | Creating | Ready _ | Failed), Ok m -> (
            map := Ready m;
            match !latest with Some shown -> show m shown | None -> ()))
  in
  let follow pos =
    latest := framing pos;
    (* The class is written here, before [show], and not by a binding of its
       own: react does not order two effects of the same rank, and [show] must
       find [el] displayed. *)
    set_hidden
      (match !map with
      | Failed -> true
      | Idle | Creating | Ready _ | Released -> Option.is_none !latest);
    match (!map, !latest) with
    | Idle, Some shown -> create shown
    | Ready m, Some shown -> show m shown
    | (Idle | Ready _), None | (Creating | Failed | Released), _ -> ()
  in
  set_hidden (Option.is_none !latest);
  Option.iter create !latest;
  let release =
    Rb.on_release (fun () ->
        match !map with
        | Ready m ->
            map := Released;
            Geo_map.remove m
        | Idle | Creating | Failed | Released -> map := Released)
  in
  {
    el;
    tap;
    bindings = [release; click; Rb.on (React.S.changes position) follow];
  }
