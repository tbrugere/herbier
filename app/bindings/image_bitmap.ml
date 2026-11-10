type t = Jv.t

let of_blob blob =
  Cap_call.on Jv.global "createImageBitmap"
    [|
      Brr.Blob.to_jv blob;
      Jv.obj [|("imageOrientation", Jv.of_string "from-image")|];
    |]
    ~ok:(fun v -> Ok v)

let width b = Jv.Int.get b "width"
let height b = Jv.Int.get b "height"
let image_src b = Brr_canvas.C2d.image_src_of_jv b
let close b = ignore (Jv.call b "close" [||])
