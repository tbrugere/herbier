open Brr

type t = {el : El.t; bindings : Rb.binding list}

let v ?(cls = []) ~opened ~set_opened text =
  match Herbier_ui_model.Long_text.collapsible text with
  | false ->
      {el = El.div ~at:(List.map Html.cls cls) [El.txt' text]; bindings = []}
  | true ->
      let el =
        Html.button ("expandable-text" :: cls)
          [El.span ~at:[Html.cls "expandable-text__body"] [El.txt' text]]
      in
      let click, b_click = Rb.click el in
      {
        el;
        bindings =
          [
            b_click;
            Rb.act click (fun () -> set_opened (not (React.S.value opened)));
            Rb.attr el "aria-expanded"
              (React.S.map (fun o -> Some (Bool.to_string o)) opened);
            Rb.class_ el "is-open" opened;
          ];
      }
