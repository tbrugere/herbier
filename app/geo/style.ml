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

type error = Not_a_style of string | Duplicate_id of string

let error_to_string = function
  | Not_a_style key -> "not a MapLibre style: bad or missing " ^ key
  | Duplicate_id id -> "the base style already has the id " ^ id

let geojson_source =
  `Assoc [("type", `String "geojson"); ("data", Features.empty)]

let layer ~id ~type_ ~source paint =
  `Assoc
    [
      ("id", `String id);
      ("type", `String type_);
      ("source", `String source);
      ("paint", `Assoc paint);
    ]

let overlay_layers c =
  [
    layer ~id:accuracy_fill_layer ~type_:"fill" ~source:accuracy_source
      [("fill-color", `String c.accuracy_fill)];
    layer ~id:accuracy_line_layer ~type_:"line" ~source:accuracy_source
      [("line-color", `String c.accuracy_line); ("line-width", `Int 1)];
    layer ~id:points_layer ~type_:"circle" ~source:observations_source
      [
        ("circle-radius", `Int 6);
        ("circle-stroke-width", `Int 3);
        ("circle-stroke-color", `String c.point_border);
        ( "circle-color",
          `List
            [
              `String "match";
              `List [`String "get"; `String Features.kind_key];
              `String (Features.kind_to_string Features.To_identify);
              `String c.to_identify;
              `String c.point;
            ] );
      ];
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
      let new_sources = [observations_source; accuracy_source] in
      let new_layers =
        [accuracy_fill_layer; accuracy_line_layer; points_layer]
      in
      let duplicate =
        match first_duplicate ~existing:(List.map fst sources) new_sources with
        | Some id -> Some id
        | None ->
            first_duplicate
              ~existing:(List.filter_map layer_id layers)
              new_layers
      in
      let* () =
        match duplicate with
        | Some id -> Error (Duplicate_id id)
        | None -> Ok ()
      in
      let sources =
        sources @ List.map (fun id -> (id, geojson_source)) new_sources
      and layers = layers @ overlay_layers colours in
      Ok
        (`Assoc
           (List.map
              (function
                | "sources", _ -> ("sources", `Assoc sources)
                | "layers", _ -> ("layers", `List layers)
                | field -> field)
              fields))
  | _ -> Error (Not_a_style "root")
