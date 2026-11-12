type colours = {
  point : string;
  point_border : string;
  selected : string;
  selected_halo : string;
  to_identify : string;
  accuracy_fill : string;
  accuracy_line : string;
}

let path = "map/positron.json"
let observations_source = "herbier-observations"
let accuracy_source = "herbier-accuracy"
let points_layer = "herbier-points"
let accuracy_fill_layer = "herbier-accuracy-fill"
let accuracy_line_layer = "herbier-accuracy-line"
let detail_zoom = 15.
let places_source = "herbier-places"
let members_source = "herbier-members"
let selection_source = "herbier-selection"
let groups_layer = "herbier-groups"
let groups_count_layer = "herbier-groups-count"
let places_layer = "herbier-places"
let members_layer = "herbier-members"
let selection_halo_layer = "herbier-selection-halo"
let selection_place_layer = "herbier-selection-place"
let selection_members_layer = "herbier-selection-members"

type error = Not_a_style of string | Duplicate_id of string

let error_to_string = function
  | Not_a_style key -> "not a MapLibre style: bad or missing " ^ key
  | Duplicate_id id -> "the base style already has the id " ^ id

let geojson_source =
  `Assoc [("type", `String "geojson"); ("data", Features.empty)]

(* Keys in the order MapLibre's style spec lists them. *)
let layer ?filter ?minzoom ?maxzoom ?layout ~id ~type_ ~source paint =
  let opt key = Option.map (fun v -> (key, v)) in
  `Assoc
    (List.concat
       [
         [
           ("id", `String id);
           ("type", `String type_);
           ("source", `String source);
         ];
         List.filter_map Fun.id
           [
             opt "filter" filter;
             opt "minzoom" (Option.map (fun z -> `Float z) minzoom);
             opt "maxzoom" (Option.map (fun z -> `Float z) maxzoom);
             opt "layout" (Option.map (fun l -> `Assoc l) layout);
           ];
         [("paint", `Assoc paint)];
       ])

let get key = `List [`String "get"; `String key]

(* Merged places add up their counts and widen their bounds, so a tapped group
   can be framed from its own properties (no async expansion-zoom call). *)
let places_source_json =
  let aggregate op key = (key, `List [`String op; get key]) in
  `Assoc
    [
      ("type", `String "geojson");
      ("data", Features.empty);
      ("cluster", `Bool true);
      ("clusterRadius", `Int 40);
      ("clusterMaxZoom", `Float (detail_zoom -. 1.));
      ( "clusterProperties",
        `Assoc
          [
            aggregate "+" Features.count_key;
            aggregate "+" Features.identified_key;
            aggregate "min" Features.west_key;
            aggregate "min" Features.south_key;
            aggregate "max" Features.east_key;
            aggregate "max" Features.north_key;
          ] );
    ]

let ring c =
  [
    ("circle-stroke-width", `Int 3);
    ("circle-stroke-color", `String c.point_border);
  ]

let disc ~radius colour c =
  (("circle-radius", `Int radius) :: ring c) @ [("circle-color", colour)]

let kind_colour c =
  `List
    [
      `String "match";
      get Features.kind_key;
      `String (Features.kind_to_string Features.To_identify);
      `String c.to_identify;
      `String c.point;
    ]

let identified_colour c =
  `List
    [
      `String "case";
      `List [`String "=="; get Features.identified_key; `Int 0];
      `String c.to_identify;
      `String c.point;
    ]

let is_group = `List [`String "has"; `String "point_count"]
let role r = `List [`String "=="; get Features.role_key; `String r]

let overlay_layers c =
  [
    layer ~id:accuracy_fill_layer ~type_:"fill" ~source:accuracy_source
      [("fill-color", `String c.accuracy_fill)];
    layer ~id:accuracy_line_layer ~type_:"line" ~source:accuracy_source
      [("line-color", `String c.accuracy_line); ("line-width", `Int 1)];
    layer ~id:points_layer ~type_:"circle" ~source:observations_source
      (disc ~radius:6 (kind_colour c) c);
    layer ~id:groups_layer ~type_:"circle" ~source:places_source
      ~filter:is_group ~maxzoom:detail_zoom
      (disc ~radius:9 (identified_colour c) c);
    layer ~id:groups_count_layer ~type_:"symbol" ~source:places_source
      ~filter:is_group ~maxzoom:detail_zoom
      ~layout:
        [
          ("text-field", `List [`String "to-string"; get Features.count_key]);
          ("text-font", `List [`String "Noto Sans Bold"]);
          ("text-size", `Int 11);
          ("text-allow-overlap", `Bool true);
        ]
      [("text-color", `String c.point_border)];
    layer ~id:places_layer ~type_:"circle" ~source:places_source
      ~filter:(`List [`String "!"; is_group])
      ~maxzoom:detail_zoom
      (disc ~radius:6 (identified_colour c) c);
    layer ~id:members_layer ~type_:"circle" ~source:members_source
      ~minzoom:detail_zoom
      (disc ~radius:6 (kind_colour c) c);
    layer ~id:selection_halo_layer ~type_:"circle" ~source:selection_source
      ~filter:(role "place") ~maxzoom:detail_zoom
      [
        ("circle-radius", `Int 28);
        ("circle-color", `String c.selected_halo);
        ("circle-stroke-width", `Int 2);
        ("circle-stroke-color", `String c.selected);
      ];
    layer ~id:selection_place_layer ~type_:"circle" ~source:selection_source
      ~filter:(role "place") ~maxzoom:detail_zoom
      (disc ~radius:7 (`String c.selected) c);
    layer ~id:selection_members_layer ~type_:"circle" ~source:selection_source
      ~filter:(role "member") ~minzoom:detail_zoom
      (disc ~radius:7 (`String c.selected) c);
  ]

let layer_id = function
  | `Assoc fields -> (
      match List.assoc_opt "id" fields with
      | Some (`String id) -> Some id
      | _ -> None)
  | _ -> None

let first_duplicate ~existing ids =
  List.find_opt (fun id -> List.mem id existing) ids

let with_overlays colours = function
  | `Assoc fields ->
      let ( let* ) = Result.bind in
      let* sources =
        match List.assoc_opt "sources" fields with
        | Some (`Assoc sources) -> Ok sources
        | Some _ | None -> Error (Not_a_style "sources")
      in
      let* layers =
        match List.assoc_opt "layers" fields with
        | Some (`List layers) -> Ok layers
        | Some _ | None -> Error (Not_a_style "layers")
      in
      let new_sources =
        [
          (observations_source, geojson_source);
          (accuracy_source, geojson_source);
          (places_source, places_source_json);
          (members_source, geojson_source);
          (selection_source, geojson_source);
        ]
      and new_layers = overlay_layers colours in
      let duplicate =
        match
          first_duplicate ~existing:(List.map fst sources)
            (List.map fst new_sources)
        with
        | Some id -> Some id
        | None ->
            first_duplicate
              ~existing:(List.filter_map layer_id layers)
              (List.filter_map layer_id new_layers)
      in
      let* () =
        match duplicate with
        | Some id -> Error (Duplicate_id id)
        | None -> Ok ()
      in
      let sources = sources @ new_sources and layers = layers @ new_layers in
      Ok
        (`Assoc
           (List.map
              (function
                | "sources", _ -> ("sources", `Assoc sources)
                | "layers", _ -> ("layers", `List layers)
                | field -> field)
              fields))
  | _ -> Error (Not_a_style "root")
