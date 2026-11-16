open Brr
module Drive_text = Herbier_ui_model.Drive_text
module Machine = Herbier_ui_model.Drive_sheet
module Drive_account = Herbier_sync_core.Auth.Drive_account
module Picker = Herbier_bindings.Google_picker
module W = Widgets

let cls = Html.cls

let v app =
  let opened, commands =
    Machine.open_
      ~stored:
        (Drive_account.email
           (React.S.value (State.account (App.state app))).drive)
      ~folder:(React.S.value (App.drive_folder app))
      ~picker:App.picker_config
  in
  (* style: a local primitive signal for the machine, set from futures'
     callbacks and click handlers (outside update steps). [released] is a ref:
     the release may run inside an update step, where no signal may be set.
     [ticket] is a ref: each token ask takes a new one, which the next Picker
     opening uses; nothing observes it. *)
  let machine, set_machine = React.S.create ~eq:Machine.equal opened in
  let released = ref false in
  let ticket = ref (Picker.ticket ()) in
  let rec feed event =
    match !released with
    | true -> ()
    | false ->
        let next, commands = Machine.step (React.S.value machine) event in
        set_machine next;
        List.iter run commands
  and run : Machine.command -> unit = function
    | Run_chooser ->
        Fut.await (App.choose_account ()) (function
          | Ok email -> feed (Chosen email)
          | Error e -> feed (Choose_failed e))
    | Ask_token email ->
        ticket := Picker.ticket ();
        Fut.await (App.folder_token app ~email) (fun r -> feed (Token r))
    | Open_picker {account; token} ->
        Fut.await (App.open_picker app !ticket ~account ~token) (function
          | Ok (Picked {id; name; _}) -> feed (Picker_picked {id; name})
          | Ok Cancelled -> feed Picker_cancelled
          | Error e -> feed (Picker_failed e))
    | Store_pick {account; folder_id; folder_name} ->
        Fut.await
          (App.store_pick app ~account {id = folder_id; name = folder_name})
          (fun r -> feed (Stored r))
    | Store_default account ->
        Fut.await (App.store_default app ~account) (fun r -> feed (Stored r))
    | Close -> ( match !released with true -> () | false -> Route.back ())
  in
  (* Not from inside the router's build step: a microtask later. *)
  Fut.await (Fut.return ()) (fun () -> List.iter run commands);
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
            Rb.on_release (fun () ->
                released := true;
                Picker.dismiss ());
          ];
        ];
  }
