open Brr
module Offline_data = Herbier_ui_model.Offline_data
module W = Widgets

let cls = Html.cls

type t = {row : El.t; after : El.t list; bindings : Rb.binding list}

let v app =
  let state, set_state =
    React.S.create ~eq:Offline_data.equal_state Offline_data.Measuring
  in
  let freeing, set_freeing = React.S.create ~eq:Bool.equal false in
  let message, set_message =
    React.S.create ~eq:(Option.equal String.equal) None
  in
  (* [k] gets the new state once it is set, after « Libérer » to say how
     much went. *)
  let measure k =
    Fut.await (App.offline_usage ()) (fun read ->
        let next =
          match read with
          | Ok usage -> Offline_data.Measured usage
          | Error e ->
              Log.cap ~scope:"réglages" "données hors-ligne" e;
              Offline_data.Unknown
        in
        set_state next;
        k next)
  in
  let free = W.Button.text "Libérer" in
  let detail = El.span ~at:[cls "t-meta"] [] in
  let row =
    El.div
      ~at:[cls "settings__row"]
      [
        El.span
          ~at:[cls "settings__text"]
          [
            El.span ~at:[cls "settings__title"] [El.txt' "Données hors-ligne"];
            detail;
          ];
        free.el;
      ]
  in
  let status =
    El.p
      ~at:
        [
          cls "t-meta";
          cls "settings__message";
          At.v (Jstr.v "role") (Jstr.v "status");
        ]
      []
  in
  let dialog =
    W.Dialog.v ~title:Offline_data.confirm_title ~text:Offline_data.confirm_text
      [
        (W.Button.Primary, "Libérer", true);
        (W.Button.Secondary, "Annuler", false);
      ]
  in
  let enabled =
    React.S.l2 ~eq:Bool.equal
      (fun state freeing -> Offline_data.can_free state && not freeing)
      state freeing
  in
  let failure_text : App.free_error -> string = function
    | Busy -> Offline_data.free_failure_text Busy
    | Store _ | Files _ -> Offline_data.free_failure_text Failed
  in
  let run () =
    let before =
      match React.S.value state with
      | Offline_data.Measured u -> u.reference_photos
      | Offline_data.(Measuring | Unknown) -> 0.
    in
    set_freeing true;
    Fut.await (App.free_reference_photos app) (fun result ->
        (* Measuring keeps « Libérer » off until the new measure lands. *)
        set_state Offline_data.Measuring;
        set_freeing false;
        match result with
        | Ok () ->
            measure (fun next ->
                set_message (Some (Offline_data.freed ~before next)))
        | Error e ->
            set_message (Some (failure_text e));
            measure (fun (_ : Offline_data.state) -> ()))
  in
  measure (fun (_ : Offline_data.state) -> ());
  {
    row;
    after = [status; dialog.el];
    bindings =
      List.concat
        [
          [
            Rb.text detail (React.S.map Offline_data.detail state);
            Rb.disabled free.el (React.S.map not enabled);
            Rb.act free.click (fun () ->
                set_message None;
                match React.S.value enabled with
                | true -> dialog.show ()
                | false -> ());
            Rb.act dialog.choice (function
              | true when React.S.value enabled -> run ()
              | true | false -> ());
            Rb.text status (React.S.map (Option.value ~default:"") message);
            Rb.attr status "hidden"
              (React.S.map
                 (function None -> Some "" | Some (_ : string) -> None)
                 message);
          ];
          free.bindings;
          dialog.bindings;
        ];
  }
