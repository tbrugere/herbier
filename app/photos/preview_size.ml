let max_side = 1600
let quality = 0.7

let fit ~width ~height =
  let long = max width height in
  match long <= max_side with
  | true -> (max 1 width, max 1 height)
  | false ->
      let scale v =
        max 1
          (Float.to_int (Float.round (float v *. float max_side /. float long)))
      in
      (scale width, scale height)
