open Brr

type t = {el : El.t; click : unit React.event; bindings : Rb.binding list}

let v ?(extra = []) ~title ~detail selected =
  let title_el = El.span ~at:[Html.cls "radio-row__title"] [] in
  let detail_el = El.span ~at:[Html.cls "t-meta"] [] in
  let el =
    Html.button
      ~at:[At.v (Jstr.v "role") (Jstr.v "radio")]
      ["radio-row"]
      [
        El.span ~at:[Html.cls "radio-row__dot"] [];
        El.span ~at:[Html.cls "radio-row__text"] (title_el :: detail_el :: extra);
      ]
  in
  let click, click_b = Rb.click el in
  {
    el;
    click;
    bindings =
      [
        click_b;
        Rb.text title_el title;
        Rb.text detail_el detail;
        Rb.class_ el "radio-row--on" selected;
        Rb.attr el "aria-checked"
          (React.S.map (fun v -> Some (string_of_bool v)) selected);
      ];
  }
