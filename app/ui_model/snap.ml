let projection_ms = 150.

(* Pointer events stop while the finger is still, so the last speed would
   otherwise outlive the gesture that produced it. *)
let max_rest_ms = 80.

let rec ascending = function
  | a :: (b :: _ as rest) -> a < b && ascending rest
  | [_] | [] -> true

let of_list snaps =
  match snaps with
  | [] -> invalid_arg "Sheet.v: no snap point"
  | snaps -> (
      match ascending snaps with
      | true -> Array.of_list snaps
      | false -> invalid_arg "Sheet.v: snap points not strictly ascending")

let clamp snaps y =
  Float.min snaps.(Array.length snaps - 1) (Float.max snaps.(0) y)

let nearest snaps y =
  let d i = Float.abs (snaps.(i) -. y) in
  let rec go best i =
    match i = Array.length snaps with
    | true -> best
    | false -> go (match d i < d best with true -> i | false -> best) (i + 1)
  in
  go 0 1

let release snaps ~at ~speed ~rest_ms =
  let speed = match rest_ms > max_rest_ms with true -> 0. | false -> speed in
  nearest snaps (at +. (speed *. projection_ms))
