type t = Jv.t
type lng_lat = {lng : float; lat : float}
type camera = {center : lng_lat; zoom : float}
type click = {at : lng_lat; ids : string list; properties : string list}

let plugin = "map"

let facade () =
  match Cap_call.plugin plugin with
  | Ok f -> Some f
  | Error e ->
      Brr.Console.error [Jstr.v (Cap_error.to_string e)];
      None

let guarded ~default meth args conv =
  match facade () with
  | None -> default
  | Some f -> (
      match conv (Jv.call f meth args) with
      | v -> v
      | exception Jv.Error e ->
          Brr.Console.error [Jstr.v meth; Jv.Error.message e];
          default
      | exception Failure message ->
          Brr.Console.error [Jstr.v meth; Jstr.v message];
          default)

let run h meth args = guarded ~default:() meth (Array.append [|h|] args) ignore

let finite v name =
  match Cap_call.float_field v name with Ok f -> Some f | Error _ -> None

let lng_lat_of v =
  match (finite v "lng", finite v "lat") with
  | Some lng, Some lat -> Some {lng; lat}
  | Some _, None | None, (Some _ | None) -> None

let strings v =
  match Jv.is_array v with
  | false -> []
  | true ->
      Jv.to_list Fun.id v
      |> List.filter_map (fun s ->
          match Jstr.to_string (Jv.typeof s) with
          | "string" -> Some (Jv.to_string s)
          | _ -> None)

let layer_list layers = Jv.of_list Jv.of_string layers

let create el ~style ~center ~zoom ~interactive =
  match Cap_call.plugin plugin with
  | Error e -> Error e
  | Ok f -> (
      let options =
        Jv.obj
          [|
            ("style", Jv.of_string style);
            ("lng", Jv.of_float center.lng);
            ("lat", Jv.of_float center.lat);
            ("zoom", Jv.of_float zoom);
            ("interactive", Jv.of_bool interactive);
          |]
      in
      match Jv.call f "create" [|Brr.El.to_jv el; options|] with
      | h -> Ok h
      | exception Jv.Error e -> Error (Cap_call.rejected (Jv.of_error e))
      | exception Failure message ->
          Error (Cap_error.Rejected {code = None; message}))

let set_style h style = run h "setStyle" [|Jv.of_string style|]

let set_data h ~source data =
  run h "setData" [|Jv.of_string source; Jv.of_string data|]

let callback f = Jv.callback ~arity:1 f

let on_click h ~layers f =
  let cb v =
    match lng_lat_of v with
    | Some at ->
        let field name =
          match Jv.find v name with Some l -> strings l | None -> []
        in
        f {at; ids = field "ids"; properties = field "properties"}
    | None -> ()
  in
  run h "onClick" [|layer_list layers; callback cb|]

let on_moveend h f =
  let cb v =
    match (lng_lat_of v, finite v "zoom") with
    | Some center, Some zoom -> f {center; zoom}
    | Some _, None | None, (Some _ | None) -> ()
  in
  run h "onMoveend" [|callback cb|]

let on_movestart h f =
  let cb v =
    match Jstr.to_string (Jv.typeof v) with
    | "boolean" -> f ~user:(Jv.to_bool v)
    | _ -> ()
  in
  run h "onMovestart" [|callback cb|]

let on_idle h f = run h "onIdle" [|callback (fun _ -> f ())|]

let on_error h f =
  let cb v =
    match Jstr.to_string (Jv.typeof v) with
    | "string" -> f (Jv.to_string v)
    | _ -> ()
  in
  run h "onError" [|callback cb|]

let center h = guarded ~default:None "getCenter" [|h|] lng_lat_of

let zoom h =
  guarded ~default:None "getZoom" [|h|] (fun v ->
      match Jstr.to_string (Jv.typeof v) with
      | "number" -> (
          match Jv.to_float v with
          | z when Float.is_finite z -> Some z
          | _ -> None)
      | _ -> None)

let fly_to h ~center ~zoom =
  run h "flyTo"
    [|Jv.of_float center.lng; Jv.of_float center.lat; Jv.of_float zoom|]

let fit_bounds h ~west ~south ~east ~north ~padding ~max_zoom ~animate =
  run h "fitBounds"
    [|
      Jv.of_float west;
      Jv.of_float south;
      Jv.of_float east;
      Jv.of_float north;
      Jv.of_int padding;
      Jv.of_float max_zoom;
      Jv.of_bool animate;
    |]

let rendered_ids h ~layers =
  guarded ~default:[] "renderedIds" [|h; layer_list layers|] strings

let resize h = run h "resize" [||]
let remove h = run h "remove" [||]
