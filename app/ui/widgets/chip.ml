open Brr

type tone = Ink | Ochre
type t = {el : El.t; click : unit React.event; bindings : Rb.binding list}

let button classes label =
  El.button
    ~at:
      (At.type' (Jstr.v "button")
      :: List.map (fun c -> At.class' (Jstr.v c)) classes)
    [El.txt' label]

let tone_class = function Ink -> "chip--ink" | Ochre -> "chip--ochre"

let filter ?(tone = Ink) ~label ~active () =
  let el = button ["chip"; tone_class tone] label in
  let click, b = Rb.click el in
  {
    el;
    click;
    bindings =
      [
        b;
        Rb.class_ el "chip--active" active;
        Rb.attr el "aria-pressed"
          (React.S.map (fun a -> Some (string_of_bool a)) active);
      ];
  }

let link label =
  let el = button ["chip"; "chip--link"] label in
  let click, b = Rb.click el in
  {el; click; bindings = [b]}

let tag label = El.span ~at:[At.class' (Jstr.v "chip-tag")] [El.txt' label]

type fill = Outline | Paper

let removable ?(fill = Outline) label =
  let x =
    El.button
      ~at:
        [
          At.type' (Jstr.v "button");
          At.class' (Jstr.v "chip-removable__x");
          At.v (Jstr.v "aria-label") (Jstr.v ("Retirer " ^ label));
        ]
      [Icon.el ~size:16 Icon.Close]
  in
  let fill =
    match fill with
    | Outline -> "chip-removable--outline"
    | Paper -> "chip-removable--paper"
  in
  let el =
    El.span
      ~at:[At.class' (Jstr.v "chip-removable"); At.class' (Jstr.v fill)]
      [El.span [El.txt' label]; x]
  in
  let click, b = Rb.click x in
  {el; click; bindings = [b]}
