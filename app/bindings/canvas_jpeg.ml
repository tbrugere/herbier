module C2d = Brr_canvas.C2d

let mime = "image/jpeg"

(* White under the image: JPEG has no alpha, and the encoder composites
   transparent pixels onto black. The default smoothing ("low") is bilinear
   without mipmaps, which aliases fine detail on a large downscale. *)
let draw ~width ~height bitmap =
  let w = float width and h = float height in
  match
    Fun.protect
      ~finally:(fun () -> Image_bitmap.close bitmap)
      (fun () ->
        let canvas = Brr_canvas.Canvas.create ~w:width ~h:height [] in
        let ctx = C2d.get_context canvas in
        C2d.set_fill_style ctx (C2d.color (Jstr.v "#fff"));
        C2d.fill_rect ctx ~x:0. ~y:0. ~w ~h;
        C2d.set_image_smoothing_quality ctx C2d.Image_smoothing_quality.high;
        C2d.draw_image_in_rect ctx
          (Image_bitmap.image_src bitmap)
          ~x:0. ~y:0. ~w ~h;
        canvas)
  with
  | canvas -> Ok canvas
  | exception Jv.Error e -> Error (Cap_error.of_jv_error e)

type encode_error = Encode of Cap_error.t | Not_jpeg of string

let encode ~quality canvas =
  Fut.map
    (function
      | Error e -> Error (Encode e)
      | Ok blob -> (
          match Jstr.to_string (Brr.Blob.type' blob) with
          | t when String.equal t mime -> Ok blob
          | t -> Error (Not_jpeg t)))
    (Canvas_blob.to_blob canvas ~type':mime ~quality)
