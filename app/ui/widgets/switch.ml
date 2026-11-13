open Brr

type t = {el : El.t; toggle : unit React.event; bindings : Rb.binding list}

let cls = Html.cls

let v ?detail ?(disabled = false) ~label on () =
  let text =
    El.span
      ~at:[cls "switch__text"]
      (El.span ~at:[cls "switch__label"] [El.txt' label]
      ::
      (match detail with
      | Some d -> [El.span ~at:[cls "t-meta"] [El.txt' d]]
      | None -> []))
  in
  let el =
    Html.button
      ~at:[At.v (Jstr.v "role") (Jstr.v "switch"); At.if' disabled At.disabled]
      ["switch"]
      [
        text;
        El.span ~at:[cls "switch__track"] [El.span ~at:[cls "switch__thumb"] []];
      ]
  in
  let toggle, b = Rb.click el in
  {
    el;
    toggle;
    bindings =
      [
        b;
        Rb.class_ el "switch--on" on;
        Rb.attr el "aria-checked"
          (React.S.map (fun v -> Some (string_of_bool v)) on);
      ];
  }
