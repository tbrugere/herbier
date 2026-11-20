module Model = Herbier_ui_model.Long_press
open Brr

type t = {
  tap : unit React.event;
  long : unit React.event;
  bindings : Rb.binding list;
}

let contextmenu : Ev.Mouse.t Ev.type' = Ev.Type.create (Jstr.v "contextmenu")

(* Brr has no touch events; only [prevent_default] is used on it. *)
let touchend : Ev.void = Ev.Type.create (Jstr.v "touchend")

let position e =
  let p = Ev.Pointer.as_mouse (Ev.as_type e) in
  (Ev.Mouse.client_x p, Ev.Mouse.client_y p)

let v el =
  let tap, send_tap = React.E.create () in
  let long, send_long = React.E.create () in
  (* style: the machine's state, its pending timer and whether the current
     press fired, platform state written only from this element's DOM
     listeners and that timer. *)
  let state = ref Model.idle and timer = ref None and fired = ref false in
  let clear () =
    Option.iter G.stop_timer !timer;
    timer := None
  in
  let rec feed input =
    let next, output = Model.step !state input in
    state := next;
    match output with
    | Model.Nothing -> ()
    | Model.Arm token ->
        clear ();
        timer :=
          Some
            (G.set_timeout ~ms:Model.hold_ms (fun () ->
                 timer := None;
                 feed (Model.Elapsed token)))
    | Model.Long ->
        fired := true;
        send_long ()
    | Model.Tap -> send_tap ()
  in
  let on type' input = Rb.listen el type' (fun e -> feed (input e)) in
  {
    tap;
    long;
    bindings =
      [
        Rb.listen el Ev.pointerdown (fun e ->
            match Ev.Pointer.is_primary (Ev.as_type e) with
            | true ->
                let x, y = position e in
                fired := false;
                feed (Model.Down {x; y})
            | false -> ());
        on Ev.pointermove (fun e ->
            let x, y = position e in
            Model.Move {x; y});
        on Ev.pointerup (fun _ -> Model.Up);
        on Ev.pointercancel (fun _ -> Model.Cancel);
        on Ev.click (fun e ->
            match Jv.Int.get (Ev.to_jv e) "detail" with
            | 0 -> Model.Activate
            | _ -> Model.Click);
        Rb.listen el contextmenu Ev.prevent_default;
        (* The lift of a long-press sends no mouse events nor click: they
           would land on what the long-press opened over the element (a
           dialog's backdrop) and blur its focused field. *)
        Rb.listen el touchend (fun e ->
            match !fired with true -> Ev.prevent_default e | false -> ());
        Rb.on_release clear;
      ];
  }
