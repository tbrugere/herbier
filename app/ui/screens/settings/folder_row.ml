open Brr
module Drive_text = Herbier_ui_model.Drive_text
module W = Widgets

type t = {el : El.t; bindings : Rb.binding list}

let cls = Html.cls

let v app ~visible =
  let row =
    React.S.l2 ~eq:Drive_text.equal_folder_row
      (fun access folder ->
        Drive_text.folder_row App.picker_config access folder)
      (App.drive_access app) (App.drive_folder app)
  in
  (* style: a local primitive signal pair: the pick running and its last
     error are this row's own state, set from futures' callbacks. *)
  let running, set_running = React.S.create ~eq:Bool.equal false in
  let error, set_error = React.S.create ~eq:(Option.equal String.equal) None in
  let choose = W.Button.text "Choisir" in
  let default = W.Button.text "Par défaut" in
  let detail = El.span ~at:[cls "t-meta"] [] in
  let line =
    El.span
      ~at:
        [
          cls "t-meta";
          cls "settings__status";
          At.v (Jstr.v "role") (Jstr.v "status");
        ]
      []
  in
  let error_el =
    El.p
      ~at:
        [
          cls "t-meta";
          cls "settings__error";
          At.v (Jstr.v "role") (Jstr.v "alert");
        ]
      []
  in
  let el =
    El.div
      ~at:[cls "settings__card"; cls "settings__folder"]
      [
        El.div
          ~at:[cls "settings__row"]
          [
            El.span
              ~at:[cls "settings__text"]
              [
                El.span ~at:[cls "settings__title"] [El.txt' "Dossier Drive"];
                detail;
                line;
                default.el;
              ];
            choose.el;
          ];
        error_el;
      ]
  in
  let reason =
    React.S.map
      ~eq:(Option.equal String.equal)
      (fun (r : Drive_text.folder_row) ->
        match r.choose with Enabled -> None | Disabled m -> Some m)
      row
  in
  let enabled =
    React.S.l2 ~eq:Bool.equal
      (fun (r : Drive_text.folder_row) running ->
        match r.choose with Enabled -> not running | Disabled _ -> false)
      row running
  in
  let pick () =
    match React.S.value enabled with
    | false -> ()
    | true ->
        set_error None;
        set_running true;
        Fut.await (App.choose_drive_folder app) (fun r ->
            set_running false;
            match r with
            | Ok () -> ()
            | Error e -> set_error (Some (Drive_text.pick_error_text e)))
  in
  let reset () =
    match React.S.value running with
    | true -> ()
    | false ->
        set_error None;
        set_running true;
        Fut.await (App.default_drive_folder app) (fun r ->
            set_running false;
            match r with
            | Ok () -> ()
            | Error (_ : Herbier_store_io.Db.error) ->
                set_error (Some (Drive_text.pick_error_text Not_saved)))
  in
  let busy = React.S.map (function true -> Some "true" | false -> None) in
  {
    el;
    bindings =
      List.concat
        [
          choose.bindings;
          default.bindings;
          [
            Rb.class_ el "is-hidden" (React.S.map not visible);
            Rb.text detail
              (React.S.map (fun (r : Drive_text.folder_row) -> r.detail) row);
            Rb.text line (React.S.map (Option.value ~default:"") reason);
            Rb.class_ line "is-hidden" (React.S.map Option.is_none reason);
            Rb.text error_el (React.S.map (Option.value ~default:"") error);
            Rb.class_ error_el "is-hidden" (React.S.map Option.is_none error);
            Rb.class_ default.el "is-hidden"
              (React.S.map
                 (fun (r : Drive_text.folder_row) -> not r.default)
                 row);
            Rb.attr choose.el "aria-disabled"
              (React.S.map
                 (function true -> None | false -> Some "true")
                 enabled);
            Rb.attr choose.el "aria-busy" (busy running);
            Rb.attr default.el "aria-disabled" (busy running);
            Rb.act choose.click pick;
            Rb.act default.click reset;
            Rb.on_release Herbier_bindings.Google_picker.dismiss;
          ];
        ];
  }
