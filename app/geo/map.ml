module Places = Herbier_domain.Places
module Observation = Herbier_domain.Observation
module Observation_id = Herbier_domain.Ids.Observation_id
module Maplibre = Herbier_bindings.Maplibre
module Cap_error = Herbier_bindings.Cap_error

type t = Maplibre.t

type error =
  | Style_fetch of string
  | Style_parse of string
  | Style of Style.error
  | Map of Cap_error.t

let error_to_string = function
  | Style_fetch m -> "style fetch: " ^ m
  | Style_parse m -> "style parse: " ^ m
  | Style e -> "style: " ^ Style.error_to_string e
  | Map e -> "map: " ^ Cap_error.to_string e

let lng_lat ({lat; lon} : Places.point) : Maplibre.lng_lat = {lng = lon; lat}
let point ({lng; lat} : Maplibre.lng_lat) : Places.point = {lat; lon = lng}

let fetch_style () =
  let open Fut.Syntax in
  let* response = Brr_io.Fetch.url (Jstr.v Style.path) in
  match response with
  | Error e ->
      Fut.return (Error (Style_fetch (Jstr.to_string (Jv.Error.message e))))
  | Ok response -> (
      match Brr_io.Fetch.Response.ok response with
      | false ->
          Fut.return
            (Error
               (Style_fetch
                  (Printf.sprintf "HTTP %d"
                     (Brr_io.Fetch.Response.status response))))
      | true ->
          let+ body =
            Brr_io.Fetch.Body.text (Brr_io.Fetch.Response.as_body response)
          in
          Result.map_error
            (fun e -> Style_fetch (Jstr.to_string (Jv.Error.message e)))
            (Result.map Jstr.to_string body))

let styled colours text =
  match Yojson.Safe.from_string text with
  | exception Yojson.Json_error m -> Error (Style_parse m)
  | base ->
      Style.with_overlays colours base
      |> Result.map Yojson.Safe.to_string
      |> Result.map_error (fun e -> Style e)

let build el ~colours ~center ~zoom ~interactive text =
  let open Result.Syntax in
  let* style = styled colours text in
  Maplibre.create el ~style ~center:(lng_lat center) ~zoom ~interactive
  |> Result.map_error (fun e -> Map e)

let create el ~colours ~center ~zoom ~interactive =
  let open Fut.Syntax in
  let+ text =
    (* Brr_io.Fetch.url raises when the fetch global is unusable; a raise here
       would leave the caller's future pending. *)
    match fetch_style () with
    | fut -> fut
    | exception Jv.Error e ->
        Fut.return (Error (Style_fetch (Jstr.to_string (Jv.Error.message e))))
  in
  Result.bind text (build el ~colours ~center ~zoom ~interactive)

let set_source m source json =
  Maplibre.set_data m ~source (Yojson.Safe.to_string json)

let set_observations m list =
  set_source m Style.observations_source (Features.observations list)

let circle_steps = 64

let set_accuracy m = function
  | None -> set_source m Style.accuracy_source Features.empty
  | Some (center, radius_m) ->
      set_source m Style.accuracy_source
        (Features.circle ~center ~radius_m ~steps:circle_steps)

type click = {at : Places.point; observations : Observation_id.t list}

let on_click m f =
  Maplibre.on_click m ~layers:[Style.points_layer] (fun {Maplibre.at; ids} ->
      f
        {
          at = point at;
          observations = List.filter_map Observation_id.of_string ids;
        })

let on_moveend m f =
  Maplibre.on_moveend m (fun {Maplibre.center; zoom} ->
      f ~center:(point center) ~zoom)

let on_idle = Maplibre.on_idle
let on_error = Maplibre.on_error
let center m = Option.map point (Maplibre.center m)
let zoom = Maplibre.zoom
let fly_to m ~center ~zoom = Maplibre.fly_to m ~center:(lng_lat center) ~zoom
let fit_max_zoom = 16.

let fit ?(max_zoom = fit_max_zoom) m
    ({south; west; north; east} : Features.bounds) ~padding_px =
  Maplibre.fit_bounds m ~west ~south ~east ~north ~padding:padding_px ~max_zoom

let rendered m =
  Maplibre.rendered_ids m ~layers:[Style.points_layer]
  |> List.filter_map Observation_id.of_string

let resize = Maplibre.resize
let remove = Maplibre.remove
