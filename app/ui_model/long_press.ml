let hold_ms = 500
let slop_px = 10.

type phase =
  | Idle
  | Pressed of {token : int; x : float; y : float}
  | Moved
  | Released
  | Fired
  | Swallowing

(* [last]: the last token handed out, so that a new press's is greater than
   every earlier one, whatever the phase. *)
type t = {phase : phase; last : int}

let idle = {phase = Idle; last = 0}

type input =
  | Down of {x : float; y : float}
  | Move of {x : float; y : float}
  | Up
  | Cancel
  | Elapsed of int
  | Click
  | Activate

type output = Nothing | Arm of int | Long | Tap

let far ~x0 ~y0 ~x ~y = Float.hypot (x -. x0) (y -. y0) > slop_px

let step t input =
  let go phase output = ({t with phase}, output) in
  match (t.phase, input) with
  | (Idle | Pressed _ | Moved | Released | Fired | Swallowing), Down {x; y} ->
      let token = t.last + 1 in
      ({phase = Pressed {token; x; y}; last = token}, Arm token)
  | (Idle | Pressed _ | Moved | Released | Fired | Swallowing), Activate ->
      go Idle Tap
  | Pressed {x = x0; y = y0; _}, Move {x; y} when far ~x0 ~y0 ~x ~y ->
      go Moved Nothing
  | Pressed {token; _}, Elapsed k when Int.equal k token -> go Fired Long
  | (Pressed _ | Moved), Up -> go Released Nothing
  | (Pressed _ | Moved | Fired | Released | Swallowing), Cancel ->
      go Idle Nothing
  | (Idle | Pressed _ | Released), Click -> go Idle Tap
  | (Moved | Fired | Swallowing), Click -> go Idle Nothing
  | Fired, Up -> go Swallowing Nothing
  | ( (Pressed _ | Moved | Released | Fired | Swallowing | Idle),
      (Move _ | Elapsed _) )
  | (Idle | Released | Swallowing), Up
  | Idle, Cancel ->
      (t, Nothing)
