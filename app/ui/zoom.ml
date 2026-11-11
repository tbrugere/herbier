type t = {scale : float; x : float; y : float}

let identity = {scale = 1.; x = 0.; y = 0.}
let max_scale = 4.
let between lo hi v = Float.max lo (Float.min hi v)

let clamp ~w ~h t =
  let scale = between 1. max_scale t.scale in
  {
    scale;
    x = between (w -. (w *. scale)) 0. t.x;
    y = between (h -. (h *. scale)) 0. t.y;
  }

let about ~w ~h t ~cx ~cy ~ratio =
  let scale = between 1. max_scale (t.scale *. ratio) in
  let k = scale /. t.scale in
  clamp ~w ~h
    {scale; x = cx -. ((cx -. t.x) *. k); y = cy -. ((cy -. t.y) *. k)}

let pan ~w ~h t ~dx ~dy = clamp ~w ~h {t with x = t.x +. dx; y = t.y +. dy}
let zoomed t = t.scale > 1.01
let settle t = match zoomed t with true -> t | false -> identity
