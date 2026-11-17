open Brr
module I = Herbier_ui_model.Identify_settings
module Plantnet = Herbier_identify.Plantnet
module W = Widgets

type t = {els : El.t list; bindings : Rb.binding list}

let cls = Html.cls
let attr name value = At.v (Jstr.v name) (Jstr.v value)
let list_id = "flora-picker-list"

type picker =
  | Closed
  | Loading
  | List_failed of string
  | Choosing of Plantnet.project list

let list_error : App.identify_error -> string = function
  | Plantnet e -> I.flora_list_error e
  | Identify_offline -> I.flora_list_offline
  | Preview_unreadable (_ : Herbier_domain.Ids.Photo_id.t) ->
      I.flora_list_generic

let shown_when el shown =
  Rb.attr el "hidden"
    (React.S.map (function true -> None | false -> Some "") shown)

(* The line under the card after a failed write of the switch or a flora. *)
let write_error () =
  let error, set_error = React.S.create ~eq:Bool.equal false in
  let el =
    El.p ~at:[cls "t-meta"; cls "settings__error"; attr "role" "alert"] []
  in
  let report = function
    | Ok () -> set_error false
    | Error (_ : Herbier_store_io.Db.error) -> set_error true
  in
  ( el,
    report,
    [
      Rb.text el
        (React.S.map
           (function
             | true -> Herbier_ui_model.Settings_text.not_saved | false -> "")
           error);
      Rb.class_ el "is-hidden" (React.S.map not error);
    ] )

let flora_block app ~report =
  let row =
    React.S.l3 ~eq:I.equal_flora_row
      (fun key (n : State.network) flora ->
        I.flora_row ~key ~online:n.online flora)
      (App.plantnet_key app)
      (State.network (App.state app))
      (App.plantnet_flora app)
  in
  let enabled =
    React.S.map ~eq:Bool.equal (fun (r : I.flora_row) -> r.enabled) row
  in
  let picker, set_picker = React.S.create ~eq:( == ) Closed in
  let set_picker p = set_picker p in
  let detail = El.span ~at:[cls "t-meta"; cls "settings__email"] [] in
  let note = El.span ~at:[cls "t-meta"; cls "settings__status"] [] in
  let button =
    Html.button
      ~at:[attr "aria-controls" list_id]
      ["settings__folder-button"]
      [
        El.span
          ~at:[cls "settings__text"]
          [
            El.span ~at:[cls "settings__title"] [El.txt' I.flora_title];
            detail;
            note;
          ];
        El.span
          ~at:[cls "settings__chevron"; attr "aria-hidden" "true"]
          [El.txt' "›"];
      ]
  in
  let click, click_b = Rb.click button in
  let field =
    W.Text_field.v ~icon:W.Icon.Search ~placeholder:I.search_placeholder ()
  in
  let ask () =
    match React.S.value (App.identify_gate app) with
    | Waiting | No_key | Offline -> ()
    | Ready k ->
        set_picker Loading;
        Fut.await
          (App.floras app ~key:(I.Key.to_string k))
          (fun result ->
            (* Closed meanwhile (a second tap, the row disabled): stays
               closed. *)
            match React.S.value picker with
            | Closed | List_failed _ | Choosing _ -> ()
            | Loading -> (
                match result with
                | Ok projects ->
                    set_picker (Choosing projects);
                    El.set_has_focus true field.input
                | Error e -> set_picker (List_failed (list_error e))))
  in
  let toggle () =
    match (React.S.value enabled, React.S.value picker) with
    | false, _ -> ()
    | true, (Loading | List_failed _ | Choosing _) ->
        field.set "";
        set_picker Closed
    | true, Closed -> ask ()
  in
  let choose (c : I.choice) =
    field.set "";
    set_picker Closed;
    Fut.await (App.set_plantnet_flora app c.flora) report
  in
  let line text =
    El.p ~at:[cls "t-meta"; cls "settings__intro"] [El.txt' text]
  in
  let render (picker, query, flora) =
    match picker with
    | Closed -> (El.div [], [])
    | Loading -> (El.div [line I.loading], [])
    | List_failed text ->
        let retry = W.Button.text I.retry in
        ( El.div [line text; El.div ~at:[cls "settings__row"] [retry.el]],
          Rb.act retry.click ask :: retry.bindings )
    | Choosing projects ->
        let rows =
          I.choices ~current:flora projects
          |> I.filter ~query
          |> List.map (fun (c : I.choice) ->
              let row =
                W.List_row.v ~title:(I.flora_detail c.flora)
                  ~meta:
                    (match c.selected with
                    | true -> I.selected_meta
                    | false -> "")
                  ()
              in
              (match c.selected with
              | true ->
                  El.set_at (Jstr.v "aria-current")
                    (Some (Jstr.v "true"))
                    row.el
              | false -> ());
              (row.el, Rb.act row.click (fun () -> choose c) :: row.bindings))
        in
        (El.div (List.map fst rows), List.concat_map snd rows)
  in
  let list_el =
    El.div ~at:[cls "pack-picker__list"; At.id (Jstr.v list_id)] []
  in
  let choosing =
    React.S.map ~eq:Bool.equal
      (function
        | Choosing _ -> true | Closed | Loading | List_failed _ -> false)
      picker
  in
  let note_text =
    React.S.map
      ~eq:(Option.equal String.equal)
      (fun (r : I.flora_row) -> r.note)
      row
  in
  ( [button; field.el; list_el],
    [
      click_b;
      Rb.text detail (React.S.map (fun (r : I.flora_row) -> r.detail) row);
      Rb.text note (React.S.map (Option.value ~default:"") note_text);
      Rb.class_ note "is-hidden" (React.S.map Option.is_none note_text);
      Rb.disabled button (React.S.map not enabled);
      Rb.attr button "aria-expanded"
        (React.S.map
           (function
             | Closed -> Some "false"
             | Loading | List_failed _ | Choosing _ -> Some "true")
           picker);
      Rb.act click toggle;
      Rb.act (React.S.changes enabled) (function
        | true -> ()
        | false ->
            field.set "";
            set_picker Closed);
      shown_when field.el choosing;
      Rb.view list_el render
        (React.S.l3 ~eq:( == )
           (fun p q f -> (p, q, f))
           picker field.value (App.plantnet_flora app));
    ]
    @ field.bindings )

let key_block app =
  let key = App.plantnet_key app in
  let loading =
    React.S.map ~eq:Bool.equal
      (function I.Loading -> true | Absent | Present _ -> false)
      key
  in
  let editing, set_editing = React.S.create ~eq:Bool.equal false in
  let saving, set_saving = React.S.create ~eq:Bool.equal false in
  let failed, set_failed = React.S.create ~eq:Bool.equal false in
  let detail = El.span ~at:[cls "t-meta"; cls "settings__email"] [] in
  let edit = W.Button.text I.key_edit in
  let row =
    El.div
      ~at:[cls "settings__row"]
      [
        El.span
          ~at:[cls "settings__text"]
          [El.span ~at:[cls "settings__title"] [El.txt' I.key_title]; detail];
        edit.el;
      ]
  in
  let field = W.Text_field.v ~placeholder:I.key_placeholder () in
  List.iter
    (fun (name, value) ->
      El.set_at (Jstr.v name) (Some (Jstr.v value)) field.input)
    [
      ("type", "password");
      ("autocomplete", "off");
      ("autocapitalize", "off");
      ("autocorrect", "off");
      ("spellcheck", "false");
    ];
  let save = W.Button.text I.key_save in
  let cancel = W.Button.text ~tone:`Ink I.key_cancel in
  let error =
    El.p ~at:[cls "t-meta"; cls "settings__error"; attr "role" "alert"] []
  in
  let editor =
    El.div
      ~at:[cls "settings__key-editor"]
      [
        field.el;
        El.div ~at:[cls "settings__key-actions"] [cancel.el; save.el];
        error;
      ]
  in
  let close () =
    field.set "";
    let step = React.Step.create () in
    set_editing ~step false;
    set_failed ~step false;
    React.Step.execute step
  in
  let open_editor () =
    match React.S.value loading with
    | true -> ()
    | false ->
        set_failed false;
        set_editing true;
        El.set_has_focus true field.input
  in
  let submit () =
    match React.S.value saving with
    | true -> ()
    | false ->
        set_saving true;
        Fut.await
          (App.set_plantnet_key app (React.S.value field.value))
          (fun result ->
            set_saving false;
            match result with
            | Ok () -> close ()
            | Error (_ : Herbier_bindings.Cap_error.t) -> set_failed true)
  in
  let help =
    El.p
      ~at:[cls "t-meta"; cls "settings__intro"; cls "settings__key-help"]
      [
        El.txt' I.key_help_before;
        El.a
          ~at:
            [
              cls "settings__link";
              At.href (Jstr.v I.key_help_url);
              attr "target" "_blank";
              attr "rel" "noopener noreferrer";
            ]
          [El.txt' I.key_help_link];
        El.txt' I.key_help_after;
      ]
  in
  ( [row; editor; help],
    [
      Rb.text detail (React.S.map ~eq:String.equal I.key_detail key);
      Rb.disabled edit.el loading;
      Rb.act edit.click open_editor;
      shown_when editor editing;
      Rb.class_ edit.el "is-hidden" editing;
      Rb.disabled save.el saving;
      Rb.act save.click submit;
      Rb.act cancel.click close;
      Rb.listen field.input Ev.keydown (fun ev ->
          match Html.enter ev with true -> submit () | false -> ());
      Rb.text error
        (React.S.map (function true -> I.key_not_saved | false -> "") failed);
      Rb.class_ error "is-hidden" (React.S.map not failed);
    ]
    @ edit.bindings
    @ field.bindings
    @ save.bindings
    @ cancel.bindings )

let v app =
  let switch =
    W.Switch.v ~label:I.on_photo_label ~detail:I.on_photo_detail
      (App.identify_on_photo app)
      ()
  in
  let error_el, report, error_b = write_error () in
  let flora_els, flora_b = flora_block app ~report in
  let key_els, key_b = key_block app in
  {
    els =
      [
        El.div ~at:[cls "settings__card"] ((switch.el :: flora_els) @ key_els);
        error_el;
        El.p ~at:[cls "t-meta"; cls "settings__footnote"] [El.txt' I.footnote];
      ];
    bindings =
      Rb.act switch.toggle (fun () ->
          Fut.await
            (App.set_identify_on_photo app
               (not (React.S.value (App.identify_on_photo app))))
            report)
      :: switch.bindings
      @ error_b
      @ flora_b
      @ key_b;
  }
