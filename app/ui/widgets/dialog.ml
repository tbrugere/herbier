open Brr

type 'a t = {
  el : El.t;
  show : unit -> unit;
  choice : 'a React.event;
  bindings : Rb.binding list;
}

let v ~title ~text actions =
  let buttons =
    List.map (fun (kind, label, value) -> (Button.v ~kind label, value)) actions
  in
  let el =
    El.div
      ~at:[At.class' (Jstr.v "confirm"); At.class' (Jstr.v "is-hidden")]
      [
        El.div
          ~at:
            [
              At.class' (Jstr.v "confirm__box");
              At.v (Jstr.v "role") (Jstr.v "dialog");
              At.v (Jstr.v "aria-modal") (Jstr.v "true");
              At.v (Jstr.v "aria-label") (Jstr.v title);
            ]
          (El.h2 ~at:[At.class' (Jstr.v "t-sheet-title")] [El.txt' title]
          :: El.p ~at:[At.class' (Jstr.v "t-body")] [El.txt' text]
          :: List.map (fun ((b : Button.t), _) -> b.el) buttons);
      ]
  in
  let visible on = El.set_class (Jstr.v "is-hidden") (not on) el in
  let show () =
    visible true;
    match buttons with
    | ((b : Button.t), _) :: _ -> El.set_has_focus true b.el
    | [] -> ()
  in
  let choice =
    React.E.select
      (List.map
         (fun ((b : Button.t), value) -> React.E.map (fun () -> value) b.click)
         buttons)
  in
  let hide = Rb.on choice (fun _ -> visible false) in
  {
    el;
    show;
    choice;
    bindings =
      hide :: List.concat_map (fun ((b : Button.t), _) -> b.bindings) buttons;
  }
