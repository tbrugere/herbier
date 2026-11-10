open Brr
module W = Widgets

(* Frames missed over a gesture, from the intervals between animation frames.
   The refresh interval is their median (60, 90 or 120 Hz screens); an
   interval of k refresh intervals missed k - 1 frames. *)
let dropped intervals =
  match List.sort Float.compare intervals with
  | [] -> 0
  | sorted ->
      let base = List.nth sorted (List.length sorted / 2) in
      List.fold_left
        (fun n dt -> n + max 0 (Float.to_int (Float.round (dt /. base)) - 1))
        0 intervals

(* Animation frames from a press on the sheet to its release (the [settled]
   event, sent before the settle transition runs); [report] gets the intervals
   between them, in ms. A press that settles nothing (a tap) is measured until
   the next press. The page also checks that a drag allocates nothing per
   frame, so a frame only writes a float into a preallocated array (intervals
   past its 1024 slots are not kept) and [tick] is one closure built in [v]. *)
module Frames = struct
  type t = {
    dts : float array;
    mutable n : int;
    mutable last : float;  (** [nan] before the first frame. *)
    mutable running : bool;
    mutable pending : bool;  (** A frame callback is requested. *)
    mutable tick : float -> unit;
  }

  let request t =
    t.pending <- true;
    ignore (G.request_animation_frame t.tick)

  let v () =
    let t =
      {
        dts = Array.make 1024 0.;
        n = 0;
        last = Float.nan;
        running = false;
        pending = false;
        tick = ignore;
      }
    in
    t.tick <-
      (fun now ->
        t.pending <- false;
        if t.running then begin
          if (not (Float.is_nan t.last)) && t.n < Array.length t.dts then begin
            t.dts.(t.n) <- now -. t.last;
            t.n <- t.n + 1
          end;
          t.last <- now;
          request t
        end);
    t

  (* A callback still pending from the previous gesture carries on as this
     one's loop, so a press never runs two loops. *)
  let start t =
    t.n <- 0;
    t.last <- Float.nan;
    t.running <- true;
    if not t.pending then request t

  let finish t report =
    if t.running then begin
      t.running <- false;
      report (Array.to_list (Array.sub t.dts 0 t.n))
    end
end

let el () =
  let rows =
    List.init 20 (fun i ->
        W.List_row.v ~thumb:W.List_row.Placeholder
          ~title:(Printf.sprintf "Observation %d" (i + 1))
          ~meta:"14:32 · 1 photo" ())
  in
  let height = El.span ~at:[At.id (Jstr.v "visible")] [] in
  let log =
    El.ol ~at:[At.id (Jstr.v "settled"); At.class' (Jstr.v "t-meta")] []
  in
  (* A header control: a tap on it must reach it, not start a drag. *)
  let rename = El.button [El.txt' "Renommer"] in
  let renamed = El.span ~at:[At.id (Jstr.v "renamed")] [] in
  let sheet =
    W.Sheet.v ~snaps:[72.; 360.; 640.]
      ~header:
        [
          El.p ~at:[At.class' (Jstr.v "t-sheet-title")] [El.txt' "Lisière nord"];
          El.p
            ~at:[At.class' (Jstr.v "t-meta")]
            [El.txt' "rayon 500 m · 6 observations"];
          rename;
        ]
      ~body:(List.map (fun (r : W.List_row.t) -> r.el) rows)
      ()
  in
  let snap i = El.button [El.txt' (Printf.sprintf "snap %d" i)] in
  (* "snap 3" is out of range: snap_to clamps it to the top. *)
  let buttons = List.init 4 snap in
  let clicks =
    List.mapi
      (fun i b -> Rb.listen b Ev.click (fun _ -> sheet.snap_to i))
      buttons
  in
  let renames, rename_click = Rb.ev rename Ev.click in
  let frames_out = El.span ~at:[At.id (Jstr.v "frames")] [] in
  let frames = Frames.v () in
  let report dts =
    let set k v = El.set_at (Jstr.v k) (Some (Jstr.v v)) frames_out in
    let longest = List.fold_left Float.max 0. dts in
    let d = dropped dts in
    set "data-frames" (string_of_int (List.length dts));
    set "data-dropped" (string_of_int d);
    set "data-longest-ms" (Printf.sprintf "%.1f" longest);
    El.set_children frames_out
      [
        El.txt'
          (Printf.sprintf "%d frames · dropped %d · longest %.1f ms"
             (List.length dts) d longest);
      ]
  in
  let root =
    El.div
      [
        El.h1 ~at:[At.class' (Jstr.v "t-screen-title")] [El.txt' "Sheet check"];
        El.p [El.txt' "visible: "; height];
        El.p [El.txt' "Renommer clicks: "; renamed];
        El.p [El.txt' "last gesture: "; frames_out];
        El.p buttons;
        log;
        sheet.el;
      ]
  in
  let bindings =
    Rb.text height
      (React.S.map
         (fun v -> string_of_int (Float.to_int (Float.round v)))
         sheet.visible)
    :: Rb.on sheet.settled (fun i ->
        El.append_children log [El.li [El.txt' (Printf.sprintf "settled %d" i)]])
    :: Rb.text renamed
         (React.S.map string_of_int (React.S.fold (fun n _ -> n + 1) 0 renames))
    :: Rb.on sheet.settled (fun _ -> Frames.finish frames report)
    :: Rb.listen sheet.el Ev.pointerdown (fun _ -> Frames.start frames)
    :: rename_click
    :: (clicks @ sheet.bindings)
  in
  Rb.hold root bindings;
  root
