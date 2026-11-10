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
