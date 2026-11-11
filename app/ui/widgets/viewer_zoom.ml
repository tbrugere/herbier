open Brr

type t = {el : El.t; reset : unit -> unit; bindings : Rb.binding list}

let slop = 10.
let tap_ms = 250.
let double_ms = 300.

let v content =
  let el = El.div ~at:[At.class' (Jstr.v "viewer-zoom")] [content] in
  (* style: the gesture's state, owned by the pointer listeners below. *)
  let z = ref Zoom.identity in
  let pointers : (int * (float * float)) list ref = ref [] in
  let start = ref None in
  (* A tap candidate: the lone finger's id, where and when it went down;
     dropped once it moves past [slop] or a second finger joins. *)
  let press = ref None in
  let last_tap = ref 0. in
  let size () = (El.bound_w el, El.bound_h el) in
  let apply () =
    let t = !z in
    El.set_inline_style (Jstr.v "transform")
      (Jstr.v
         (Printf.sprintf "translate(%gpx, %gpx) scale(%g)" t.x t.y t.scale))
      content;
    El.set_class (Jstr.v "is-zoomed") (Zoom.zoomed t) el
  in
  let local e =
    let p = Ev.Pointer.as_mouse (Ev.as_type e) in
    (Ev.Mouse.client_x p -. El.bound_x el, Ev.Mouse.client_y p -. El.bound_y el)
  in
  let id e = Ev.Pointer.id (Ev.as_type e) in
  let mid () =
    match !pointers with
    | [(_, (x1, y1)); (_, (x2, y2))] ->
        Some
          ( ((x1 +. x2) /. 2., (y1 +. y2) /. 2.),
            Float.hypot (x2 -. x1) (y2 -. y1) )
    | _ -> None
  in
  let begin_gesture () = start := Option.map (fun m -> (m, !z)) (mid ()) in
  let now () = Performance.now_ms G.performance in
  let down =
    Rb.listen el Ev.pointerdown (fun e ->
        let p = local e in
        pointers := (id e, p) :: List.remove_assoc (id e) !pointers;
        (press :=
           match !pointers with [_] -> Some (id e, p, now ()) | _ -> None);
        begin_gesture ())
  in
  let move =
    Rb.listen el Ev.pointermove (fun e ->
        match List.assoc_opt (id e) !pointers with
        | None -> ()
        | Some (px, py) -> (
            let ((x, y) as p) = local e in
            pointers := (id e, p) :: List.remove_assoc (id e) !pointers;
            (match !press with
            | Some (i, (x0, y0), _)
              when i = id e && Float.hypot (x -. x0) (y -. y0) > slop ->
                press := None
            | _ -> ());
            let w, h = size () in
            match (!start, mid ()) with
            | Some (((cx0, cy0), d0), z0), Some ((cx, cy), d) when d0 > 0. ->
                let zoomed =
                  Zoom.about ~w ~h z0 ~cx:cx0 ~cy:cy0 ~ratio:(d /. d0)
                in
                z := Zoom.pan ~w ~h zoomed ~dx:(cx -. cx0) ~dy:(cy -. cy0);
                apply ()
            | _ when Zoom.zoomed !z ->
                z := Zoom.pan ~w ~h !z ~dx:(x -. px) ~dy:(y -. py);
                apply ()
            | _ -> ()))
  in
  (* Every finger up: a pinch ending under ×1.01 goes back to ×1. *)
  let settle () =
    match !pointers with
    | [] ->
        z := Zoom.settle !z;
        apply ()
    | _ :: _ -> ()
  in
  let toggle e =
    let t = now () in
    match t -. !last_tap < double_ms with
    | true ->
        let w, h = size () in
        let cx, cy = local e in
        (z :=
           match Zoom.zoomed !z with
           | true -> Zoom.identity
           | false -> Zoom.about ~w ~h !z ~cx ~cy ~ratio:2.5);
        apply ();
        last_tap := 0.
    | false -> last_tap := t
  in
  let lift e =
    pointers := List.remove_assoc (id e) !pointers;
    begin_gesture ()
  in
  let up e =
    let tap =
      match !press with
      | Some (i, (x0, y0), t0) ->
          let x, y = local e in
          i = id e
          && Float.hypot (x -. x0) (y -. y0) <= slop
          && now () -. t0 < tap_ms
      | None -> false
    in
    press := None;
    lift e;
    settle ();
    if tap then toggle e
  in
  (* The browser took the gesture (a swipe of the track): never a tap. *)
  let cancel e =
    press := None;
    lift e;
    settle ()
  in
  let b_up = Rb.listen el Ev.pointerup up in
  let b_cancel = Rb.listen el Ev.pointercancel cancel in
  {
    el;
    reset =
      (fun () ->
        z := Zoom.identity;
        apply ());
    bindings = [down; move; b_up; b_cancel];
  }
