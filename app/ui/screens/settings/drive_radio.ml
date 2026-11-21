open Brr
module Drive_text = Herbier_ui_model.Drive_text
module Machine = Herbier_ui_model.Drive_sheet
module Original_target = Herbier_domain.Photo.Original_target

type t = {radio : El.t; status : El.t; bindings : Rb.binding list}

let cls = Html.cls

let v app ~storage ~(set_error : ?step:React.step -> string option -> unit) =
  let state = App.state app in
  let option =
    React.S.l2 ~eq:Drive_text.equal_drive_option
      (fun (a : State.account) folder ->
        Drive_text.drive_option ~drive:a.drive ~storage:a.storage folder)
      (State.account state) (App.drive_folder app)
  in
  (* style: the running flow, a handle kept between the tap and its close,
     and released with the screen; [flow] mirrors its machine for the DOM. *)
  let running = ref None in
  let flow, set_flow = React.S.create ~eq:(Option.equal Machine.equal) None in
  let closed (m : Machine.t) =
    running := None;
    let step = React.Step.create () in
    set_flow ~step None;
    set_error ~step (Option.map Drive_text.sheet_error_text m.error);
    React.Step.execute step
  in
  let start () =
    let f = Drive_flow.create app ~purpose:Turn_on in
    running := Some f;
    let step = React.Step.create () in
    set_flow ~step (Some (Drive_flow.state f));
    set_error ~step None;
    React.Step.execute step;
    Drive_flow.run f ~on_change:(fun m -> set_flow (Some m)) ~on_close:closed
  in
  let choose () =
    match
      Drive_text.drive_option_starts ~storage:(React.S.value storage)
        ~running:(Option.is_some !running) (React.S.value option)
    with
    | true -> start ()
    | false -> ()
  in
  let optional f = React.S.map ~eq:(Option.equal String.equal) f option in
  let chosen = optional (fun (o : Drive_text.drive_option) -> o.chosen) in
  let reason =
    optional (fun (o : Drive_text.drive_option) ->
        match o.choose with Disabled r -> Some r | Enabled -> None)
  in
  let chosen_el = El.span ~at:[cls "t-meta"; cls "radio-row__chosen"] [] in
  let reason_el = El.span ~at:[cls "t-meta"; cls "radio-row__reason"] [] in
  let row =
    Radio_row.v ~extra:[chosen_el; reason_el]
      ~title:
        (React.S.map ~eq:String.equal
           (fun (o : Drive_text.drive_option) -> o.title)
           option)
      ~detail:
        (React.S.map ~eq:String.equal
           (fun (o : Drive_text.drive_option) -> o.detail)
           option)
      (React.S.map ~eq:Bool.equal
         (function Original_target.Drive -> true | App_only -> false)
         storage)
  in
  let status =
    El.p
      ~at:
        [
          cls "t-meta";
          cls "settings__status-line";
          At.v (Jstr.v "role") (Jstr.v "status");
        ]
      []
  in
  let hidden s = React.S.map Option.is_none s in
  {
    radio = row.el;
    status;
    bindings =
      row.bindings
      @ [
          Rb.act row.click choose;
          Rb.text chosen_el (React.S.map (Option.value ~default:"") chosen);
          Rb.class_ chosen_el "is-hidden" (hidden chosen);
          Rb.text reason_el (React.S.map (Option.value ~default:"") reason);
          Rb.class_ reason_el "is-hidden" (hidden reason);
          Rb.class_ row.el "radio-row--disabled"
            (React.S.map Option.is_some reason);
          Rb.attr row.el "aria-disabled"
            (React.S.map (Option.map (fun (_ : string) -> "true")) reason);
          Rb.attr row.el "aria-busy"
            (React.S.map
               (function
                 | Some m when Machine.busy m -> Some "true"
                 | Some (_ : Machine.t) | None -> None)
               flow);
          Rb.text status
            (React.S.map
               (fun m ->
                 Option.value ~default:"" (Option.bind m Machine.status_line))
               flow);
          Rb.on_release (fun () -> Option.iter Drive_flow.release !running);
        ];
  }
