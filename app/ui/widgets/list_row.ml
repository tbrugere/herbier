open Brr

type thumb = Image of string | Placeholder
type tone = Normal | To_identify
type t = {el : El.t; click : unit React.event; bindings : Rb.binding list}

let cls c = At.class' (Jstr.v c)

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
  | Placeholder -> El.span ~at:[cls "list-row__thumb"] []

let v ?thumb ?(tone = Normal) ~title ~meta () =
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
  let el =
    El.button ~at:[At.type' (Jstr.v "button"); cls "list-row"] children
  in
  let click, b = Rb.click el in
  {el; click; bindings = [b]}
