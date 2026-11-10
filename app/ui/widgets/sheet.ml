open Brr

type t = {
  el : El.t;
  visible : float React.signal;
  settled : int React.event;
  snap_to : int -> unit;
  bindings : Rb.binding list;
}

let cls c = At.class' (Jstr.v c)

(* A press becomes a drag once the finger has moved this far, in px. Below it
   the gesture is a tap, left to whatever the header holds. *)
let slop = 6.

type drag = {
  pointer : int;
  from_y : float;
  from_visible : float;
  mutable last_y : float;
  mutable last_t : float;
  mutable speed : float;  (** px/ms, upward positive *)
}

type gesture = Idle | Pressed of {pointer : int; y : float} | Dragging of drag

let pointer_id e = Ev.Pointer.id (Ev.as_type e)
let pointer_y e = Ev.Mouse.client_y (Ev.Pointer.as_mouse (Ev.as_type e))

(* The translation on screen now, mid-transition included: the y of the
   computed matrix, [matrix(a, b, c, d, x, y)] or [matrix3d(...)]. *)
let shown_ty el =
  let m = Jstr.to_string (El.computed_style (Jstr.v "transform") el) in
  match (String.index_opt m '(', String.index_opt m ')') with
  | Some i, Some j when j > i -> (
      let args = String.split_on_char ',' (String.sub m (i + 1) (j - i - 1)) in
      let ty =
        match String.starts_with ~prefix:"matrix3d" m with
        | true -> List.nth_opt args 13
        | false -> List.nth_opt args 5
      in
      match ty with
      | Some s -> float_of_string_opt (String.trim s)
      | None -> None)
  | _ -> None

let v ~snaps ?(start = 0) ~header ~body () =
  let snaps = Snap.of_list snaps in
  let last = Array.length snaps - 1 in
  let hi = snaps.(last) in
  let clamp_i i = max 0 (min last i) in
  let start = clamp_i start in
  let visible, set_visible = React.S.create ~eq:Float.equal snaps.(start) in
  let settled, send_settled = React.E.create () in
  let grab =
    El.div
      ~at:[cls "sheet__grab"]
      (El.div ~at:[cls "sheet__handle"] [] :: header)
  in
  let hidden i = Printf.sprintf "%gpx" (hi -. snaps.(i)) in
  (* style: inline custom properties because both come from the caller's
     snaps, known only at runtime: the sheet's height, and how much of it is
     below the screen at the current snap point, which pads the body so its
     end can scroll into view. *)
  let el =
    El.div
      ~at:
        [
          cls "sheet";
          At.style
            (Jstr.v
               (Printf.sprintf "--sheet-height:%gpx;--sheet-hidden:%s" hi
                  (hidden start)));
        ]
      [grab; El.div ~at:[cls "sheet__body"] body]
  in
  let settling = Jstr.v "sheet--settling" in
  let snap_to i =
    let i = clamp_i i in
    El.set_class settling true el;
    El.set_inline_style (Jstr.v "--sheet-hidden") (Jstr.v (hidden i)) el;
    let step = React.Step.create () in
    set_visible ~step snaps.(i);
    send_settled ~step i;
    React.Step.execute step
  in
  (* style: a ref because one gesture's state lives across DOM pointer events
     and never leaves this closure (style 2.2). *)
  let gesture = ref Idle in
  (* A second finger does not take over a drag in progress. *)
  let down e =
    match !gesture with
    | Dragging _ -> ()
    | Idle | Pressed _ ->
        gesture := Pressed {pointer = pointer_id e; y = pointer_y e}
  in
  let start_drag e pointer =
    (* Mid-settle, [visible] already holds the target: the sheet freezes where
       the transition has got to instead of jumping there. *)
    let from_visible =
      match El.class' settling el with
      | false -> React.S.value visible
      | true -> (
          match shown_ty el with
          | Some ty -> Snap.clamp snaps (hi -. ty)
          | None -> React.S.value visible)
    in
    El.set_class settling false el;
    set_visible from_visible;
    (* Captured only now, so that a tap on a header control still gets its
       click. *)
    Herbier_bindings.Pointer_capture.set grab pointer;
    let y = pointer_y e in
    Dragging
      {
        pointer;
        from_y = y;
        from_visible;
        last_y = y;
        last_t = Ev.timestamp_ms e;
        speed = 0.;
      }
  in
  let move e =
    let id = pointer_id e in
    match !gesture with
    | Pressed p when p.pointer = id -> (
        match Float.abs (pointer_y e -. p.y) >= slop with
        | true -> gesture := start_drag e id
        | false -> ())
    | Dragging d when d.pointer = id ->
        let y = pointer_y e and t = Ev.timestamp_ms e in
        (match t > d.last_t with
        | true -> d.speed <- (d.last_y -. y) /. (t -. d.last_t)
        | false -> ());
        d.last_y <- y;
        d.last_t <- t;
        set_visible (Snap.clamp snaps (d.from_visible +. d.from_y -. y))
    | Idle | Pressed _ | Dragging _ -> ()
  in
  (* A lift flings along the gesture; a cancel or a lost capture only settles
     on the nearest point. *)
  let finish ~fling e =
    let id = pointer_id e in
    match !gesture with
    | Pressed p when p.pointer = id -> gesture := Idle
    | Dragging d when d.pointer = id ->
        gesture := Idle;
        let speed = match fling with true -> d.speed | false -> 0. in
        snap_to
          (Snap.release snaps ~at:(React.S.value visible) ~speed
             ~rest_ms:(Ev.timestamp_ms e -. d.last_t))
    | Idle | Pressed _ | Dragging _ -> ()
  in
  (* Only grab's own capture: the handle's implicit touch capture is lost,
     and bubbles up here, when [start_drag] moves it to grab. *)
  let lost e =
    match Jv.strict_equal (El.to_jv grab) (Ev.target_to_jv (Ev.target e)) with
    | true -> finish ~fling:false e
    | false -> ()
  in
  let transform =
    React.S.map
      (fun v ->
        "translate3d(0,"
        ^ Jstr.to_string (Jstr.of_float ~frac:1 (hi -. v))
        ^ "px,0)")
      visible
  in
  {
    el;
    visible;
    settled;
    snap_to;
    bindings =
      [
        Rb.style el "transform" transform;
        Rb.listen grab Ev.pointerdown down;
        Rb.listen grab Ev.pointermove move;
        Rb.listen grab Ev.pointerup (finish ~fling:true);
        Rb.listen grab Ev.pointercancel (finish ~fling:false);
        Rb.listen grab Ev.lostpointercapture lost;
      ];
  }
