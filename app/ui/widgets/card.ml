open Brr

type cover =
  | Photo of string
  | Preview of string
  | Loading of string
  | No_photo of string

type t = {
  el : El.t;
  click : unit React.event;
  long : unit React.event;
  bindings : Rb.binding list;
}

let cls = Html.cls

(* Spans, not divs: they sit inside a button, which allows phrasing content
   only. The Sass makes them blocks. *)
let span c children = El.span ~at:[cls c] children

let names ~name ~sci extra =
  let sci =
    match sci with None -> [] | Some s -> [span "card-plant__sci" [El.txt' s]]
  in
  span "card-plant__names"
    ((span "card-plant__name" [El.txt' name] :: sci) @ extra)

let plant ?(long_press = false) ~name ~sci cover =
  let modifier, children =
    match cover with
    | Photo url ->
        ( "card-plant--photo",
          [
            El.img
              ~at:
                [
                  At.src (Jstr.v url);
                  At.v (Jstr.v "alt") Jstr.empty;
                  At.v (Jstr.v "loading") (Jstr.v "lazy");
                ]
              ();
            span "card-plant__scrim" [];
            names ~name ~sci [];
          ] )
    | Preview path ->
        ( "card-plant--photo",
          [
            Preview_img.v ~cls:["card-plant__preview"] path;
            span "card-plant__scrim" [];
            names ~name ~sci [];
          ] )
    | Loading label ->
        ( "card-plant--loading",
          [span "card-plant__loading" [El.txt' label]; names ~name ~sci []] )
    | No_photo mention ->
        ( "card-plant--bare",
          [names ~name ~sci [span "card-plant__mention" [El.txt' mention]]] )
  in
  let el = Html.button ["card-plant"; modifier] children in
  let press = Long_press.optional long_press el in
  {el; click = press.tap; long = press.long; bindings = press.bindings}

let panel children = El.div ~at:[cls "card"] children
