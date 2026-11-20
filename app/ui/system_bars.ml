open Brr
module Bars = Herbier_ui_model.System_bars
module Cap = Herbier_bindings.Cap_system_bars

let surface_of_route = function
  | Route.Modal (Route.Record | Route.Viewer _) -> Bars.Dark
  | Route.Tab _ | Route.Dev _
  | Route.Modal
      Route.(
        ( Tags | Manage_tags | Plant _ | Edit_plant _ | New_plant
        | Observation _ | Change_species _ | Move_point _ | Identify _ | Saved _
        | Search _ | Link_species _ | Intercepted _ | Drive_folder )) ->
      Bars.Light

(* style: module state, as Transition's observer: set once by the dev hooks. *)
let observer = ref (fun (_ : Bars.t) -> ())
let observe f = observer := f

let send (bar, surface) =
  let bar =
    match bar with
    | Bars.Status -> Cap.Status_bar
    | Navigation -> Navigation_bar
  in
  let style = match surface with Bars.Light -> Cap.Light | Dark -> Dark in
  Fut.await (Cap.set_style ~bar ~style) (function
    | Ok () | Error (Herbier_bindings.Cap_error.Unavailable _) -> ()
    | Error e ->
        Log.error ~scope:"system bars" "setStyle failed"
          (Herbier_bindings.Cap_error.to_string e))

type inputs = {route : Bars.surface; offline_banner : bool}

let start ~route ~offline_banner =
  let inputs =
    React.S.l2
      ~eq:(fun a b ->
        Bars.equal_surface a.route b.route
        && Bool.equal a.offline_banner b.offline_banner)
      (fun r offline_banner -> {route = surface_of_route r; offline_banner})
      route offline_banner
  in
  (* style: the value last applied, read and written by [apply] only. *)
  let applied = ref None in
  let apply () =
    let {route; offline_banner} = React.S.value inputs in
    let next =
      Bars.resolve ~route ~overlays:(Overlay.surfaces ()) ~offline_banner
    in
    match Bars.changes ~previous:!applied next with
    | [] -> ()
    | changes ->
        applied := Some next;
        !observer next;
        List.iter send changes
  in
  Overlay.on_change apply;
  Rb.hold (Document.root G.document)
    [Rb.on (React.S.changes inputs) (fun (_ : inputs) -> apply ())];
  apply ()
