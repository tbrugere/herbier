(* Native checks of app/geo/features.ml and app/geo/style.ml (copied into
   this directory by test/geo/dune, hence the unqualified [Features] and
   [Style] module names). [web/map/positron.json] doubles as the shipped
   style and the fixture of the with_overlays tests, read relative to the
   test's working directory ([_build/default/test/geo]). *)

module Observation = Herbier_domain.Observation
module Places = Herbier_domain.Places
module Ids = Herbier_domain.Ids

(* ---------- building test observations ---------- *)

(* Zero-padded, as test/domain/test_places.ml does, so ids compare in the
   order of [n]. *)
let id_string n = Printf.sprintf "00000000-0000-4000-8000-%012d" n

let obs_id n =
  match Ids.Observation_id.of_string (id_string n) with
  | Some id -> id
  | None -> Alcotest.failf "Observation_id.of_string %S gave None" (id_string n)

let plant_id n =
  match Ids.Plant_id.of_string (id_string n) with
  | Some id -> id
  | None -> Alcotest.failf "Plant_id.of_string %S gave None" (id_string n)

let base_time = 1_700_000_000.

let time s =
  match Ptime.of_float_s (base_time +. float_of_int s) with
  | Some t -> t
  | None -> Alcotest.failf "Ptime.of_float_s rejected offset %d" s

(* [obs ?plant ?(deleted=false) ~id ~at pos]: an observation with id number
   [id], taken [at] seconds after [base_time], at [pos] (lat, lon). *)
let obs ?plant ?(deleted = false) ~id ~at pos : Observation.t =
  let at = time at in
  {
    Observation.id = obs_id id;
    plant_id = plant;
    at;
    position =
      Option.map
        (fun (lat, lon) -> {Observation.lat; lon; accuracy_m = None})
        pos;
    place_label = None;
    place_derived = None;
    note = None;
    created_at = at;
    updated_at = at;
    deleted_at = (if deleted then Some at else None);
  }

let string_of_id (o : Observation.t) = Ids.Observation_id.to_string o.id

(* Unplaceable observations shared by several suites: no position, deleted,
   nan and infinite coordinates (same shape as test_places.ml's [unplaceable]). *)
let no_position = obs ~id:90 ~at:0 None
let deleted = obs ~id:91 ~at:1 ~deleted:true (Some (48.1, 7.2))
let nan_lat = obs ~id:92 ~at:2 (Some (Float.nan, 7.2))
let inf_lon = obs ~id:93 ~at:3 (Some (48.1, Float.infinity))
let unplaceable = [no_position; deleted; nan_lat; inf_lon]

(* ---------- testables ---------- *)

let yojson =
  Alcotest.testable
    (fun f j -> Format.pp_print_string f (Yojson.Safe.pretty_to_string j))
    Yojson.Safe.equal

let bounds =
  let pp f (b : Features.bounds) =
    Format.fprintf f "{south = %.9g; west = %.9g; north = %.9g; east = %.9g}"
      b.south b.west b.north b.east
  in
  let equal (a : Features.bounds) (b : Features.bounds) =
    Float.equal a.south b.south
    && Float.equal a.west b.west
    && Float.equal a.north b.north
    && Float.equal a.east b.east
  in
  Alcotest.testable pp equal

let style_error =
  let pp f = function
    | Style.Not_a_style key -> Format.fprintf f "Not_a_style %S" key
    | Style.Duplicate_id id -> Format.fprintf f "Duplicate_id %S" id
  in
  let equal a b =
    match (a, b) with
    | Style.Not_a_style a, Style.Not_a_style b -> String.equal a b
    | Style.Duplicate_id a, Style.Duplicate_id b -> String.equal a b
    | Style.Not_a_style _, Style.Duplicate_id _
    | Style.Duplicate_id _, Style.Not_a_style _ ->
        false
  in
  Alcotest.testable pp equal

(* ---------- small JSON helpers ---------- *)

let collection features =
  `Assoc [("type", `String "FeatureCollection"); ("features", `List features)]

let point_feature ~id ~lon ~lat ~kind =
  `Assoc
    [
      ("type", `String "Feature");
      ( "geometry",
        `Assoc
          [
            ("type", `String "Point");
            ("coordinates", `List [`Float lon; `Float lat]);
          ] );
      ("properties", `Assoc [("id", `String id); ("kind", `String kind)]);
    ]

let ids_of (j : Yojson.Safe.t) : string list =
  let open Yojson.Safe.Util in
  j
  |> member "features"
  |> to_list
  |> List.map (fun f -> f |> member "properties" |> member "id" |> to_string)

(* ---------- Features.observations ---------- *)

let observations_empty_is_the_empty_collection () =
  Alcotest.(check yojson)
    "Features.observations [] equals Features.empty" Features.empty
    (Features.observations []);
  Alcotest.(check yojson)
    "Features.empty is the empty FeatureCollection" (collection [])
    Features.empty

let observations_identified () =
  let o = obs ~id:1 ~at:0 ~plant:(plant_id 1) (Some (48.1, 7.2)) in
  Alcotest.(check yojson)
    "one feature, lon before lat, kind identified"
    (collection
       [
         point_feature ~id:(string_of_id o) ~lon:7.2 ~lat:48.1 ~kind:"identified";
       ])
    (Features.observations [o])

let observations_to_identify () =
  let o = obs ~id:1 ~at:0 (Some (48.1, 7.2)) in
  Alcotest.(check yojson)
    "no plant_id gives kind to_identify"
    (collection
       [
         point_feature ~id:(string_of_id o) ~lon:7.2 ~lat:48.1
           ~kind:"to_identify";
       ])
    (Features.observations [o])

let observations_unplaceable_absent () =
  let placeable = obs ~id:1 ~at:0 (Some (48.1, 7.2)) in
  let result = Features.observations (unplaceable @ [placeable]) in
  let open Yojson.Safe.Util in
  Alcotest.(check int)
    "only the placeable observation gives a feature" 1
    (result |> member "features" |> to_list |> List.length);
  Alcotest.(check (list string))
    "the feature is the placeable one"
    [string_of_id placeable]
    (ids_of result)

let observations_order_ascending_at () =
  let newest = obs ~id:1 ~at:2 (Some (48.0, 7.0)) in
  let middle = obs ~id:2 ~at:1 (Some (48.1, 7.1)) in
  let oldest = obs ~id:3 ~at:0 (Some (48.2, 7.2)) in
  let expected_ids = List.map string_of_id [oldest; middle; newest] in
  List.iter
    (fun (name, input) ->
      Alcotest.(check (list string))
        (Printf.sprintf "%s comes out ascending by at" name)
        expected_ids
        (ids_of (Features.observations input)))
    [
      ("newest-first input", [newest; middle; oldest]);
      ("already-ascending input", [oldest; middle; newest]);
      ("middle-first input", [middle; oldest; newest]);
    ]

let observations_order_tie_by_id () =
  let a = obs ~id:1 ~at:0 (Some (48.0, 7.0)) in
  let b = obs ~id:2 ~at:0 (Some (48.1, 7.1)) in
  let expected_ids = List.map string_of_id [a; b] in
  Alcotest.(check (list string))
    "equal at: ascending by id although b is given first" expected_ids
    (ids_of (Features.observations [b; a]));
  Alcotest.(check (list string))
    "same with a given first" expected_ids
    (ids_of (Features.observations [a; b]))

let observations_round_trips_through_json_text () =
  let o1 = obs ~id:1 ~at:0 ~plant:(plant_id 1) (Some (48.1, 7.2)) in
  let o2 = obs ~id:2 ~at:1 (Some (48.2, 7.3)) in
  let result = Features.observations (unplaceable @ [o1; o2]) in
  let text = Yojson.Safe.to_string result in
  Alcotest.(check bool)
    "the serialised text never spells out nan or inf" false
    (let lower = String.lowercase_ascii text in
     let contains sub =
       let n = String.length sub and m = String.length lower in
       let rec go i =
         i + n <= m && (String.sub lower i n = sub || go (i + 1))
       in
       go 0
     in
     contains "nan" || contains "inf");
  Alcotest.(check yojson)
    "parsing the text back gives an equal value" result
    (Yojson.Safe.from_string text)

(* ---------- Features.bounds ---------- *)

let bounds_none_for_empty_or_unplaceable () =
  Alcotest.(check (option bounds)) "[] has no bounds" None (Features.bounds []);
  Alcotest.(check (option bounds))
    "all-unplaceable has no bounds" None
    (Features.bounds unplaceable)

let bounds_one_point () =
  let o = obs ~id:1 ~at:0 (Some (48.1, 7.2)) in
  Alcotest.(check (option bounds))
    "south = north, west = east"
    (Some {Features.south = 48.1; west = 7.2; north = 48.1; east = 7.2})
    (Features.bounds [o])

let bounds_three_points_ignore_unplaceable () =
  let a = obs ~id:1 ~at:0 (Some (48.0, 7.0)) in
  let b = obs ~id:2 ~at:1 (Some (49.0, 6.0)) in
  let c = obs ~id:3 ~at:2 (Some (47.5, 8.0)) in
  let extreme = obs ~id:4 ~at:3 ~deleted:true (Some (90., 180.)) in
  Alcotest.(check (option bounds))
    "min/max per axis; the deleted extreme point is ignored"
    (Some {Features.south = 47.5; west = 6.0; north = 49.0; east = 8.0})
    (Features.bounds [a; b; c; extreme])

(* ---------- Features.circle ---------- *)

let ring_of (j : Yojson.Safe.t) : (float * float) list =
  let open Yojson.Safe.Util in
  match j |> member "features" |> to_list with
  | [feature] -> (
      match feature |> member "geometry" |> member "coordinates" |> to_list with
      | [ring] ->
          ring
          |> to_list
          |> List.map (fun pos ->
              match pos |> to_list with
              | [lon; lat] -> (to_number lon, to_number lat)
              | _ -> Alcotest.fail "a ring vertex is not [lon, lat]")
      | _ -> Alcotest.fail "the polygon does not have exactly one ring")
  | _ -> Alcotest.fail "the circle does not have exactly one feature"

let centre : Places.point = {lat = 48.06; lon = 7.0}

let circle_shape () =
  let ring =
    ring_of (Features.circle ~center:centre ~radius_m:1000. ~steps:64)
  in
  Alcotest.(check int) "a 64-step ring has 65 positions" 65 (List.length ring);
  Alcotest.(check (pair (float 0.) (float 0.)))
    "the last position equals the first" (List.hd ring) (List.nth ring 64)

let circle_vertices_are_at_radius () =
  List.iter
    (fun radius_m ->
      let ring = ring_of (Features.circle ~center:centre ~radius_m ~steps:64) in
      List.iteri
        (fun i (lon, lat) ->
          let d = Places.distance_m centre {Places.lat; lon} in
          Alcotest.(check (float 0.01))
            (Printf.sprintf "vertex %d is radius_m=%g from the centre" i
               radius_m)
            radius_m d)
        ring)
    [25.; 5000.]

let circle_bearings () =
  let ring =
    ring_of (Features.circle ~center:centre ~radius_m:1000. ~steps:64)
  in
  let lon0, lat0 = List.nth ring 0 in
  Alcotest.(check (float 1e-9))
    "vertex 0 keeps the centre's longitude" centre.lon lon0;
  Alcotest.(check bool)
    "vertex 0 is north of the centre" true (lat0 > centre.lat);
  let lon16, lat16 = List.nth ring 16 in
  Alcotest.(check bool)
    "vertex 16 of 64 is east of the centre" true (lon16 > centre.lon);
  Alcotest.(check (float 1e-4))
    "vertex 16 of 64 is close to the centre's latitude" centre.lat lat16

let circle_empty_on_invalid_input () =
  List.iter
    (fun (name, radius_m) ->
      Alcotest.(check yojson)
        name Features.empty
        (Features.circle ~center:centre ~radius_m ~steps:64))
    [
      ("radius 0 gives empty", 0.);
      ("negative radius gives empty", -1.);
      ("nan radius gives empty", Float.nan);
      ("infinite radius gives empty", Float.infinity);
    ];
  Alcotest.(check yojson)
    "fewer than 3 steps gives empty" Features.empty
    (Features.circle ~center:centre ~radius_m:1000. ~steps:2);
  List.iter
    (fun (name, center) ->
      Alcotest.(check yojson)
        name Features.empty
        (Features.circle ~center ~radius_m:1000. ~steps:64))
    [
      ("a nan latitude gives empty", {Places.lat = Float.nan; lon = 7.0});
      ("an infinite latitude gives empty", {lat = Float.infinity; lon = 7.0});
      ("a nan longitude gives empty", {lat = 48.; lon = Float.nan});
      ("an infinite longitude gives empty", {lat = 48.; lon = Float.infinity});
    ]

let circle_three_steps () =
  let ring =
    ring_of (Features.circle ~center:centre ~radius_m:1000. ~steps:3)
  in
  Alcotest.(check int) "a 3-step ring has 4 positions" 4 (List.length ring);
  Alcotest.(check (pair (float 0.) (float 0.)))
    "the last position equals the first" (List.hd ring) (List.nth ring 3)

let circle_at_the_pole () =
  let ring =
    ring_of
      (Features.circle
         ~center:{lat = 88.302683353501408; lon = 0.}
         ~radius_m:188733. ~steps:64)
  in
  List.iteri
    (fun i (lon, lat) ->
      Alcotest.(check bool)
        (Printf.sprintf "vertex %d is finite" i)
        true
        (Float.is_finite lon && Float.is_finite lat))
    ring

(* ---------- Style.with_overlays ---------- *)

let positron_text =
  In_channel.with_open_bin "../../web/map/positron.json" In_channel.input_all

let positron = Yojson.Safe.from_string positron_text

let colours : Style.colours =
  {
    point = "POINT";
    point_border = "POINT_BORDER";
    selected = "SELECTED";
    selected_halo = "SELECTED_HALO";
    to_identify = "TO_IDENTIFY";
    accuracy_fill = "ACCURACY_FILL";
    accuracy_line = "ACCURACY_LINE";
  }

let with_overlays_ok base =
  match Style.with_overlays colours base with
  | Ok result -> result
  | Error e -> Alcotest.failf "with_overlays: %s" (Style.error_to_string e)

let positron_fixture_sanity () =
  let open Yojson.Safe.Util in
  Alcotest.(check int)
    "style version is 8" 8
    (positron |> member "version" |> to_int);
  Alcotest.(check bool)
    "sources contains openmaptiles" true
    (positron |> member "sources" |> to_assoc |> List.mem_assoc "openmaptiles");
  Alcotest.(check bool)
    "layers is non-empty" true
    (positron |> member "layers" |> to_list <> []);
  Alcotest.(check bool)
    "has glyphs" true
    (positron |> member "glyphs" |> to_string_option <> None);
  Alcotest.(check bool)
    "has sprite" true
    (positron |> member "sprite" |> to_string_option <> None)

let layers_appended_after_the_base () =
  let result = with_overlays_ok positron in
  let open Yojson.Safe.Util in
  let base_layers = positron |> member "layers" |> to_list in
  let layers = result |> member "layers" |> to_list in
  let n = List.length base_layers in
  Alcotest.(check int) "3 layers appended" (n + 3) (List.length layers);
  Alcotest.(check (list yojson))
    "the base layers are unchanged and in order" base_layers
    (List.filteri (fun i _ -> i < n) layers);
  let overlay_ids =
    List.filteri (fun i _ -> i >= n) layers
    |> List.map (fun l -> l |> member "id" |> to_string)
  in
  Alcotest.(check (list string))
    "overlay layer ids, in order"
    [Style.accuracy_fill_layer; Style.accuracy_line_layer; Style.points_layer]
    overlay_ids

let sources_appended_after_the_base () =
  let result = with_overlays_ok positron in
  let open Yojson.Safe.Util in
  let base_sources = positron |> member "sources" |> to_assoc in
  let sources = result |> member "sources" |> to_assoc in
  let n = List.length base_sources in
  Alcotest.(check (list (pair string yojson)))
    "the base sources are unchanged and in order" base_sources
    (List.filteri (fun i _ -> i < n) sources);
  let overlay = List.filteri (fun i _ -> i >= n) sources in
  Alcotest.(check (list string))
    "overlay source ids, in order"
    [Style.observations_source; Style.accuracy_source]
    (List.map fst overlay);
  List.iter
    (fun (_, source) ->
      Alcotest.(check yojson)
        "an overlay source is a geojson source holding Features.empty"
        (`Assoc [("type", `String "geojson"); ("data", Features.empty)])
        source)
    overlay

let other_top_level_keys_unchanged () =
  let result = with_overlays_ok positron in
  let open Yojson.Safe.Util in
  let others j =
    List.filter
      (fun (k, _) -> not (List.mem k ["sources"; "layers"]))
      (to_assoc j)
  in
  Alcotest.(check (list string))
    "the base has version, glyphs and sprite among its other keys" []
    (List.filter
       (fun k -> not (List.mem_assoc k (others positron)))
       ["version"; "glyphs"; "sprite"]);
  Alcotest.(check (list (pair string yojson)))
    "every top-level key other than sources and layers is unchanged, in order"
    (others positron) (others result)

let layer_by_id result id =
  let open Yojson.Safe.Util in
  result
  |> member "layers"
  |> to_list
  |> List.find (fun l -> String.equal (l |> member "id" |> to_string) id)

let colours_applied_to_the_overlay_layers () =
  let result = with_overlays_ok positron in
  let open Yojson.Safe.Util in
  let points = layer_by_id result Style.points_layer in
  let points_paint = points |> member "paint" in
  Alcotest.(check string)
    "the points layer is a circle layer" "circle"
    (points |> member "type" |> to_string);
  Alcotest.(check yojson)
    "circle-color is the kind match expression"
    (`List
       [
         `String "match";
         `List [`String "get"; `String "kind"];
         `String "to_identify";
         `String colours.to_identify;
         `String colours.point;
       ])
    (points_paint |> member "circle-color");
  Alcotest.(check string)
    "circle-stroke-color is point_border" colours.point_border
    (points_paint |> member "circle-stroke-color" |> to_string);
  Alcotest.(check int)
    "circle-radius is 6" 6
    (points_paint |> member "circle-radius" |> to_int);
  Alcotest.(check int)
    "circle-stroke-width is 3" 3
    (points_paint |> member "circle-stroke-width" |> to_int);
  Alcotest.(check string)
    "the points layer reads the observations source" Style.observations_source
    (points |> member "source" |> to_string);
  let fill = layer_by_id result Style.accuracy_fill_layer in
  Alcotest.(check string)
    "the accuracy fill layer is a fill layer" "fill"
    (fill |> member "type" |> to_string);
  Alcotest.(check string)
    "fill-color is accuracy_fill" colours.accuracy_fill
    (fill |> member "paint" |> member "fill-color" |> to_string);
  Alcotest.(check string)
    "the fill layer reads the accuracy source" Style.accuracy_source
    (fill |> member "source" |> to_string);
  let line = layer_by_id result Style.accuracy_line_layer in
  Alcotest.(check string)
    "the accuracy line layer is a line layer" "line"
    (line |> member "type" |> to_string);
  Alcotest.(check string)
    "line-color is accuracy_line" colours.accuracy_line
    (line |> member "paint" |> member "line-color" |> to_string);
  Alcotest.(check int)
    "line-width is 1" 1
    (line |> member "paint" |> member "line-width" |> to_int);
  Alcotest.(check string)
    "the line layer reads the accuracy source" Style.accuracy_source
    (line |> member "source" |> to_string)

let overlay_paints_are_exact () =
  let result = with_overlays_ok positron in
  let open Yojson.Safe.Util in
  let paint id = layer_by_id result id |> member "paint" in
  Alcotest.(check yojson)
    "the whole points paint"
    (`Assoc
       [
         ("circle-radius", `Int 6);
         ("circle-stroke-width", `Int 3);
         ("circle-stroke-color", `String colours.point_border);
         ( "circle-color",
           `List
             [
               `String "match";
               `List [`String "get"; `String "kind"];
               `String "to_identify";
               `String colours.to_identify;
               `String colours.point;
             ] );
       ])
    (paint Style.points_layer);
  Alcotest.(check yojson)
    "the whole accuracy fill paint"
    (`Assoc [("fill-color", `String colours.accuracy_fill)])
    (paint Style.accuracy_fill_layer);
  Alcotest.(check yojson)
    "the whole accuracy line paint"
    (`Assoc
       [("line-color", `String colours.accuracy_line); ("line-width", `Int 1)])
    (paint Style.accuracy_line_layer)

let kind_matches_the_style () =
  Alcotest.(check string) "Features.kind_key" "kind" Features.kind_key;
  Alcotest.(check string)
    "To_identify" "to_identify"
    (Features.kind_to_string Features.To_identify);
  Alcotest.(check string)
    "Identified" "identified"
    (Features.kind_to_string Features.Identified)

let with_overlays_errors () =
  let check msg expected input =
    Alcotest.(check (result yojson style_error))
      msg (Error expected)
      (Style.with_overlays colours input)
  in
  check "a null root is not a style" (Style.Not_a_style "root") `Null;
  check "an empty-list root is not a style" (Style.Not_a_style "root")
    (`List []);
  check "an object without layers" (Style.Not_a_style "layers")
    (`Assoc [("sources", `Assoc [])]);
  check "layers not a list" (Style.Not_a_style "layers")
    (`Assoc [("sources", `Assoc []); ("layers", `String "nope")]);
  check "an object without sources" (Style.Not_a_style "sources")
    (`Assoc [("layers", `List [])]);
  check "sources not an object" (Style.Not_a_style "sources")
    (`Assoc [("sources", `List []); ("layers", `List [])])

let with_overlays_duplicate_ids () =
  let base_with_layer =
    `Assoc
      [
        ("sources", `Assoc []);
        ("layers", `List [`Assoc [("id", `String Style.points_layer)]]);
      ]
  in
  Alcotest.(check (result yojson style_error))
    "a layer named herbier-points already present"
    (Error (Style.Duplicate_id Style.points_layer))
    (Style.with_overlays colours base_with_layer);
  let base_with_source =
    `Assoc
      [
        ("sources", `Assoc [(Style.accuracy_source, `Assoc [])]);
        ("layers", `List []);
      ]
  in
  Alcotest.(check (result yojson style_error))
    "a source named herbier-accuracy already present"
    (Error (Style.Duplicate_id Style.accuracy_source))
    (Style.with_overlays colours base_with_source);
  List.iter
    (fun id ->
      Alcotest.(check (result yojson style_error))
        (Printf.sprintf "a layer named %s already present" id)
        (Error (Style.Duplicate_id id))
        (Style.with_overlays colours
           (`Assoc
              [
                ("sources", `Assoc []);
                ("layers", `List [`Assoc [("id", `String id)]]);
              ])))
    [Style.accuracy_fill_layer; Style.accuracy_line_layer; Style.points_layer];
  Alcotest.(check (result yojson style_error))
    "a source named herbier-observations already present"
    (Error (Style.Duplicate_id Style.observations_source))
    (Style.with_overlays colours
       (`Assoc
          [
            ("sources", `Assoc [(Style.observations_source, `Assoc [])]);
            ("layers", `List []);
          ]));
  let once = with_overlays_ok positron in
  match Style.with_overlays colours once with
  | Error (Style.Duplicate_id _) -> ()
  | Error (Style.Not_a_style key) ->
      Alcotest.failf
        "re-applying with_overlays to its own output gave Not_a_style %s" key
  | Ok _ ->
      Alcotest.fail "re-applying with_overlays to its own output should fail"

let literal_ids () =
  Alcotest.(check string) "Style.path" "map/positron.json" Style.path;
  Alcotest.(check string)
    "Style.observations_source" "herbier-observations" Style.observations_source;
  Alcotest.(check string)
    "Style.accuracy_source" "herbier-accuracy" Style.accuracy_source;
  Alcotest.(check string)
    "Style.points_layer" "herbier-points" Style.points_layer;
  Alcotest.(check string)
    "Style.accuracy_fill_layer" "herbier-accuracy-fill"
    Style.accuracy_fill_layer;
  Alcotest.(check string)
    "Style.accuracy_line_layer" "herbier-accuracy-line"
    Style.accuracy_line_layer

let contains ~sub s =
  let n = String.length sub in
  let rec go i =
    i + n <= String.length s
    && (String.equal (String.sub s i n) sub || go (i + 1))
  in
  go 0

let error_to_string_covers_both_constructors () =
  Alcotest.(check bool)
    "Not_a_style names the key" true
    (contains ~sub:"layers"
       (Style.error_to_string (Style.Not_a_style "layers")));
  Alcotest.(check bool)
    "Duplicate_id names the id" true
    (contains ~sub:"herbier-points"
       (Style.error_to_string (Style.Duplicate_id "herbier-points")))

let tests =
  [
    ( "Features.observations [] equals Features.empty",
      `Quick,
      observations_empty_is_the_empty_collection );
    ( "Features.observations: an identified observation gives kind identified",
      `Quick,
      observations_identified );
    ( "Features.observations: plant_id = None gives kind to_identify",
      `Quick,
      observations_to_identify );
    ( "Features.observations drops unplaceable observations",
      `Quick,
      observations_unplaceable_absent );
    ( "Features.observations orders features ascending by at",
      `Quick,
      observations_order_ascending_at );
    ( "Features.observations breaks an equal at by ascending id",
      `Quick,
      observations_order_tie_by_id );
    ( "Features.observations never serialises nan or infinity",
      `Quick,
      observations_round_trips_through_json_text );
    ( "Features.bounds is None for [] and all-unplaceable",
      `Quick,
      bounds_none_for_empty_or_unplaceable );
    ("Features.bounds of one point collapses to it", `Quick, bounds_one_point);
    ( "Features.bounds takes the min/max of placeable points only",
      `Quick,
      bounds_three_points_ignore_unplaceable );
    ( "Features.circle of 64 steps is a 65-vertex closed ring",
      `Quick,
      circle_shape );
    ( "Features.circle: every vertex is radius_m from the centre",
      `Quick,
      circle_vertices_are_at_radius );
    ( "Features.circle: vertex 0 is north, vertex 16 of 64 is east",
      `Quick,
      circle_bearings );
    ( "Features.circle is empty for an invalid radius, steps or centre",
      `Quick,
      circle_empty_on_invalid_input );
    ( "Features.circle with 3 steps is a closed 4-position ring",
      `Quick,
      circle_three_steps );
    ( "Features.circle stays finite close to the pole",
      `Quick,
      circle_at_the_pole );
    ( "Features' kind strings are the ones Style matches",
      `Quick,
      kind_matches_the_style );
    ( "the recorded positron.json has the expected shape",
      `Quick,
      positron_fixture_sanity );
    ( "Style.with_overlays appends 3 layers after the base",
      `Quick,
      layers_appended_after_the_base );
    ( "Style.with_overlays appends 2 geojson sources after the base",
      `Quick,
      sources_appended_after_the_base );
    ( "Style.with_overlays leaves other top-level keys unchanged",
      `Quick,
      other_top_level_keys_unchanged );
    ( "Style.with_overlays applies colours to the overlay layers",
      `Quick,
      colours_applied_to_the_overlay_layers );
    ( "Style.with_overlays: the overlay paints are exactly the expected ones",
      `Quick,
      overlay_paints_are_exact );
    ( "Style.with_overlays rejects a base that is not a style",
      `Quick,
      with_overlays_errors );
    ( "Style.with_overlays rejects a duplicate source or layer id",
      `Quick,
      with_overlays_duplicate_ids );
    ( "Style's path and overlay ids are the literals the plan gives",
      `Quick,
      literal_ids );
    ( "Style.error_to_string covers both constructors",
      `Quick,
      error_to_string_covers_both_constructors );
  ]

let () = Alcotest.run "geo" [("features and style", tests)]
