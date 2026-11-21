open Brr

type thumb = Image of string | Preview of string | Placeholder
type tone = Normal | To_identify

type t = {
  el : El.t;
  click : unit React.event;
  long : unit React.event;
  bindings : Rb.binding list;
}

let cls = Html.cls

let thumb_el = function
  | Image url ->
      El.span
        ~at:[cls "list-row__thumb"]
        [
          El.img
            ~at:
              [
                At.src (Jstr.v url);
                At.v (Jstr.v "alt") Jstr.empty;
                At.v (Jstr.v "loading") (Jstr.v "lazy");
              ]
            ();
        ]
  | Preview path ->
      El.span
        ~at:[cls "list-row__thumb"]
        [Preview_img.v ~cls:["list-row__preview"] path]
  | Placeholder -> El.span ~at:[cls "list-row__thumb"] []

let v ?(long_press = false) ?thumb ?(tone = Normal) ~title ~meta () =
  let title_cls =
    match tone with
    | Normal -> [cls "list-row__title"]
    | To_identify -> [cls "list-row__title"; cls "list-row__title--to-identify"]
  in
  let text =
    El.span
      ~at:[cls "list-row__text"]
      [
        El.span ~at:title_cls [El.txt' title];
        El.span ~at:[cls "list-row__meta"] [El.txt' meta];
      ]
  in
  let chevron =
    El.span
      ~at:[cls "list-row__chevron"; At.v (Jstr.v "aria-hidden") (Jstr.v "true")]
      [El.txt' "›"]
  in
  let children =
    match thumb with
    | None -> [text; chevron]
    | Some t -> [thumb_el t; text; chevron]
  in
  let el = Html.button ["list-row"] children in
  let press = Long_press.optional long_press el in
  {el; click = press.tap; long = press.long; bindings = press.bindings}
