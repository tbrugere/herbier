open Brr

type t = {el : El.t; toggle : unit React.event; bindings : Rb.binding list}

let cls c = At.class' (Jstr.v c)

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
    El.button
      ~at:
        [
          At.type' (Jstr.v "button");
          cls "switch";
          At.v (Jstr.v "role") (Jstr.v "switch");
          At.if' disabled At.disabled;
        ]
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
