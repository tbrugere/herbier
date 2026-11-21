open Brr
module Drive_text = Herbier_ui_model.Drive_text
module Machine = Herbier_ui_model.Drive_sheet
module W = Widgets

let cls = Html.cls

let v app =
  let flow = Drive_flow.create app ~purpose:Change in
  let opened = Drive_flow.state flow in
  (* style: a local primitive signal for the machine, set from the flow's
     callbacks (futures and click handlers, outside update steps). *)
  let machine, set_machine = React.S.create ~eq:Machine.equal opened in
  let field =
    W.Text_field.v ~action:"Renommer"
      ~action_enabled:(React.S.map ~eq:Bool.equal Machine.can_rename machine)
      ~label:"Nom du dossier" ~enterkeyhint:"done" ~value:opened.folder
      ~placeholder:(Herbier_photos.Drive.default_folder_name :> string)
      ()
  in
  (* A rename done: the field shows the name Drive now has. *)
  let on_change (m : Machine.t) =
    let before = React.S.value machine in
    set_machine m;
    match String.equal before.folder m.folder with
    | true -> ()
    | false -> field.set m.folder
  in
  Drive_flow.run flow ~on_change ~on_close:(fun (_ : Machine.t) ->
      Route.back ());
  let feed = Drive_flow.feed flow in
  let back = W.Icon_button.el ~label:"Retour" W.Icon.Arrow_back in
  let back_click, back_b = Rb.click back in
  let account_el = El.span ~at:[cls "drive-sheet__account"] [] in
  let other = W.Button.text "" in
  let name_label =
    El.span
      ~at:[cls "t-meta"; cls "drive-sheet__label"]
      [El.txt' "Nom du dossier"]
  in
  let name_el = El.div ~at:[cls "drive-sheet__name"] [name_label; field.el] in
  let help_el =
    El.p
      ~at:[cls "t-meta"; cls "drive-sheet__help"]
      [El.txt' Drive_text.folder_help]
  in
  let status_el =
    El.p
      ~at:
        [
          cls "t-meta";
          cls "drive-sheet__status";
          At.v (Jstr.v "role") (Jstr.v "status");
        ]
      []
  in
  let error_el =
    El.p
      ~at:
        [
          cls "t-meta";
          cls "drive-sheet__error";
          At.v (Jstr.v "role") (Jstr.v "alert");
        ]
      []
  in
  let el =
    El.div
      ~at:[cls "screen"; cls "drive-sheet"]
      [
        El.div
          ~at:[cls "modal-header"]
          [
            back;
            El.span ~at:[cls "modal-header__title"] [El.txt' "Dossier Drive"];
          ];
        El.div ~at:[cls "drive-sheet__card"] [account_el; other.el];
        name_el;
        help_el;
        status_el;
        error_el;
      ]
  in
  let map f = React.S.map f machine in
  let text_of f = React.S.map ~eq:String.equal f machine in
  let error =
    React.S.map
      ~eq:(Option.equal String.equal)
      (fun (m : Machine.t) -> Option.map Drive_text.sheet_error_text m.error)
      machine
  in
  let status =
    React.S.map ~eq:(Option.equal String.equal) Machine.status_line machine
  in
  let aria_disabled enabled =
    map (fun m -> match enabled m with true -> None | false -> Some "true")
  in
  let when_idle event () =
    match Machine.busy (React.S.value machine) with
    | true -> ()
    | false -> feed (event ())
  in
  let rename = when_idle (fun () -> Tap_rename (React.S.value field.value)) in
  {
    Screen.el;
    ready = Screen.now;
    bindings =
      List.concat
        [
          other.bindings;
          field.bindings;
          [
            back_b;
            Rb.act back_click (fun () -> feed Tap_close);
            Rb.text account_el (text_of Machine.account_line);
            Rb.text other.el (text_of Machine.other_account_label);
            Rb.attr other.el "aria-disabled"
              (aria_disabled (fun m -> not (Machine.busy m)));
            Rb.act other.click (when_idle (fun () -> Tap_other_account));
            Rb.act field.action rename;
            (* The text sent is not edited while it is renamed: the answer
               replaces it. *)
            Rb.attr field.input "readonly"
              (map (fun m ->
                   match Machine.busy m with true -> Some "" | false -> None));
            Rb.listen field.input Ev.keydown (fun ev ->
                match Html.enter ev with true -> rename () | false -> ());
            Rb.text status_el (React.S.map (Option.value ~default:"") status);
            Rb.class_ status_el "is-hidden" (React.S.map Option.is_none status);
            Rb.text error_el (React.S.map (Option.value ~default:"") error);
            Rb.class_ error_el "is-hidden" (React.S.map Option.is_none error);
            Rb.attr el "aria-busy"
              (map (fun m ->
                   match Machine.busy m with
                   | true -> Some "true"
                   | false -> None));
            Rb.on_release (fun () -> Drive_flow.release flow);
          ];
        ];
  }
