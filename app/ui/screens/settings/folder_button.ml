open Brr
module Drive_text = Herbier_ui_model.Drive_text
module W = Widgets

type t = {el : El.t; bindings : Rb.binding list}

let cls = Html.cls

let prompt_row app =
  let state = App.state app in
  let prompt =
    React.S.l3
      ~eq:(Option.equal Drive_text.equal_prompt)
      (fun (a : State.account) access q ->
        Drive_text.drive_prompt ~storage:a.storage
          ~pending:(Drive_text.pending_count q)
          access)
      (State.account state) (App.drive_access app) (App.upload_queue app)
  in
  let action =
    React.S.map
      ~eq:(Option.equal String.equal)
      (fun p -> Option.bind p (fun (p : Drive_text.prompt) -> p.action))
      prompt
  in
  let text = El.span ~at:[cls "t-meta"; cls "settings__text"] [] in
  let authorize = W.Button.text "" in
  let el =
    El.div
      ~at:[cls "settings__prompt"; cls "settings__folder-prompt"]
      [text; authorize.el]
  in
  ( el,
    Rb.text text
      (React.S.map
         (function Some (p : Drive_text.prompt) -> p.text | None -> "")
         prompt)
    :: Rb.class_ el "is-hidden" (React.S.map Option.is_none prompt)
    :: Rb.text authorize.el (React.S.map (Option.value ~default:"") action)
    :: Rb.class_ authorize.el "is-hidden" (React.S.map Option.is_none action)
    :: Rb.act authorize.click (fun () -> App.authorize_drive app)
    :: authorize.bindings )

let v app ~visible =
  let button =
    React.S.l2 ~eq:Drive_text.equal_folder_button
      (fun (a : State.account) folder ->
        Drive_text.folder_button ~drive:a.drive folder)
      (State.account (App.state app))
      (App.drive_folder app)
  in
  let detail = El.span ~at:[cls "t-meta"; cls "settings__email"] [] in
  let reason = El.span ~at:[cls "t-meta"; cls "settings__status"] [] in
  let row =
    Html.button
      ["settings__folder-button"]
      [
        El.span
          ~at:[cls "settings__text"]
          [
            El.span ~at:[cls "settings__title"] [El.txt' "Dossier Drive"];
            detail;
            reason;
          ];
        El.span
          ~at:
            [
              cls "settings__chevron";
              At.v (Jstr.v "aria-hidden") (Jstr.v "true");
            ]
          [El.txt' "›"];
      ]
  in
  let click, click_b = Rb.click row in
  let prompt_el, prompt_b = prompt_row app in
  let el =
    El.div ~at:[cls "settings__card"; cls "settings__folder"] [row; prompt_el]
  in
  let open_sheet () =
    match (React.S.value button).choose with
    | Enabled -> Route.go (Route.Modal Route.Drive_folder)
    | Disabled (_ : string) -> ()
  in
  let reason_text =
    React.S.map
      ~eq:(Option.equal String.equal)
      (fun (b : Drive_text.folder_button) ->
        match b.choose with Enabled -> None | Disabled reason -> Some reason)
      button
  in
  {
    el;
    bindings =
      click_b
      :: Rb.class_ el "is-hidden" (React.S.map not visible)
      :: Rb.text detail
           (React.S.map (fun (b : Drive_text.folder_button) -> b.detail) button)
      :: Rb.text reason (React.S.map (Option.value ~default:"") reason_text)
      :: Rb.class_ reason "is-hidden" (React.S.map Option.is_none reason_text)
      :: Rb.attr row "aria-disabled"
           (React.S.map
              (fun (b : Drive_text.folder_button) ->
                match b.choose with
                | Enabled -> None
                | Disabled (_ : string) -> Some "true")
              button)
      :: Rb.act click open_sheet
      :: prompt_b;
  }
