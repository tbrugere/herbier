open Brr

(* Hidden where the screen has its own offline line (4d's pill) and where
   the emulator checks read the page (dev pages). *)
let covered = function
  | Route.Modal Route.Record | Route.Dev _ -> true
  | Route.Tab _
  | Route.Modal
      Route.(
        ( Tags | Plant _ | Edit_plant _ | New_plant | Observation _
        | Change_species _ | Move_point _ | Identify _ | Recorded _ | Viewer _
        | Search _ | Link_species _ | Intercepted _ | Drive_folder )) ->
      false

let mount app ~route =
  let text =
    React.S.l2
      ~eq:(Option.equal String.equal)
      (fun ({online} : State.network) queue ->
        Herbier_ui_model.Network_text.banner ~online
          ~pending:(Herbier_ui_model.Drive_text.pending_count queue))
      (State.network (App.state app))
      (App.upload_queue app)
  in
  let shown =
    React.S.l2 ~eq:Bool.equal
      (fun text route -> Option.is_some text && not (covered route))
      text route
  in
  let flag = React.S.map (function true -> Some "" | false -> None) shown in
  let el =
    El.div
      ~at:
        [
          At.class' (Jstr.v "offline-banner");
          At.v (Jstr.v "role") (Jstr.v "status");
          At.v (Jstr.v "aria-live") (Jstr.v "polite");
        ]
      []
  in
  Rb.hold el
    [
      Rb.text el (React.S.map (Option.value ~default:"") text);
      Rb.attr el "hidden"
        (React.S.map (function true -> None | false -> Some "") shown);
      Rb.attr (Document.root G.document) "data-offline" flag;
    ];
  El.append_children (Document.body G.document) [el];
  shown
