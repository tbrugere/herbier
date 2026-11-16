open Brr
module Drive_text = Herbier_ui_model.Drive_text
module Machine = Herbier_ui_model.Drive_sheet
module W = Widgets

let cls = Html.cls

let v app =
  let flow = Drive_flow.create app ~purpose:Change in
  (* style: a local primitive signal for the machine, set from the flow's
     callbacks (futures and click handlers, outside update steps). *)
  let machine, set_machine =
    React.S.create ~eq:Machine.equal (Drive_flow.state flow)
  in
  Drive_flow.run flow
    ~on_change:(fun m -> set_machine m)
    ~on_close:(fun (_ : Machine.t) -> Route.back ());
  let feed = Drive_flow.feed flow in
  let back = W.Icon_button.el ~label:"Retour" W.Icon.Arrow_back in
  let back_click, back_b = Rb.click back in
  let account_el = El.span ~at:[cls "drive-sheet__account"] [] in
  let other = W.Button.text "" in
  let folder_el = El.p ~at:[cls "t-meta"; cls "drive-sheet__folder"] [] in
  let browse = W.Button.v ~kind:Secondary "Parcourir mes dossiers" in
  let default = W.Button.v ~kind:Secondary "Par défaut" in
  let default_detail =
    El.p
      ~at:[cls "t-meta"; cls "drive-sheet__detail"]
      [El.txt' "Dossier « Herbier » créé par l’app dans ce compte"]
  in
  let default_el =
    El.div ~at:[cls "drive-sheet__default"] [default.el; default_detail]
  in
  let note_el = El.p ~at:[cls "t-meta"; cls "drive-sheet__note"] [] in
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
        folder_el;
        browse.el;
        default_el;
        status_el;
        note_el;
        error_el;
      ]
  in
  let map f = React.S.map f machine in
  let text_of f = React.S.map ~eq:String.equal f machine in
  let error =
    React.S.map
      ~eq:(Option.equal String.equal)
      (fun (m : Machine.t) -> Option.map Drive_text.pick_error_text m.error)
      machine
  in
  let optional f = React.S.map ~eq:(Option.equal String.equal) f machine in
  let note = optional Machine.picker_note in
  let status = optional Machine.status_line in
  let folder = optional Machine.folder_line in
  let aria_disabled enabled =
    map (fun m -> match enabled m with true -> None | false -> Some "true")
  in
  let when_idle event () =
    match Machine.busy (React.S.value machine) with
    | true -> ()
    | false -> feed event
  in
  {
    Screen.el;
    ready = Screen.now;
    bindings =
      List.concat
        [
          other.bindings;
          browse.bindings;
          default.bindings;
          [
            back_b;
            Rb.act back_click (fun () -> feed Tap_close);
            Rb.text account_el (text_of Machine.account_line);
            Rb.text other.el (text_of Machine.other_account_label);
            Rb.attr other.el "aria-disabled"
              (aria_disabled (fun m -> not (Machine.busy m)));
            Rb.act other.click (when_idle Tap_other_account);
            Rb.text folder_el (React.S.map (Option.value ~default:"") folder);
            Rb.class_ folder_el "is-hidden" (React.S.map Option.is_none folder);
            Rb.class_ browse.el "is-hidden"
              (map (fun (m : Machine.t) ->
                   match m.picker with
                   | Picker_ready -> false
                   | Picker_unconfigured -> true));
            Rb.attr browse.el "aria-disabled" (aria_disabled Machine.can_browse);
            Rb.act browse.click (when_idle Tap_browse);
            Rb.class_ default_el "is-hidden"
              (map (fun m -> not (Machine.can_default m)));
            Rb.act default.click (when_idle Tap_default);
            Rb.text status_el (React.S.map (Option.value ~default:"") status);
            Rb.class_ status_el "is-hidden" (React.S.map Option.is_none status);
            Rb.text note_el (React.S.map (Option.value ~default:"") note);
            Rb.class_ note_el "is-hidden" (React.S.map Option.is_none note);
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
