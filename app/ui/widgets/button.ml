open Brr

type kind = Primary | Secondary | Danger
type t = {el : El.t; click : unit React.event; bindings : Rb.binding list}

let cls c = At.class' (Jstr.v c)

let make classes children =
  let el =
    El.button ~at:(At.type' (Jstr.v "button") :: List.map cls classes) children
  in
  let click, b = Rb.click el in
  {el; click; bindings = [b]}

let kind_class = function
  | Primary -> "button--primary"
  | Secondary -> "button--secondary"
  | Danger -> "button--danger"

let icon_els = function None -> [] | Some i -> [Icon.el ~size:22 i]

let v ?(kind = Primary) ?icon label =
  make ["button"; kind_class kind] (icon_els icon @ [El.span [El.txt' label]])

let dynamic ?(kind = Primary) ?icon label =
  let span = El.span [] in
  let b = make ["button"; kind_class kind] (icon_els icon @ [span]) in
  {b with bindings = Rb.text span label :: b.bindings}

let text ?(tone = `Moss) label =
  let tone =
    match tone with
    | `Moss -> "text-button--moss"
    | `Ink -> "text-button--ink"
    | `Danger -> "text-button--danger"
  in
  make ["text-button"; tone] [El.txt' label]
