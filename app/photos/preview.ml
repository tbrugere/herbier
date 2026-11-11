module Photo = Herbier_domain.Photo
module Observation_id = Herbier_domain.Ids.Observation_id
module Photo_id = Herbier_domain.Ids.Photo_id
module Cap_error = Herbier_bindings.Cap_error
module Image_bitmap = Herbier_bindings.Image_bitmap
module Db = Herbier_store.Db
module Files = Herbier_store.Files
module C2d = Brr_canvas.C2d

type error =
  | Decode of Cap_error.t
  | Encode of Cap_error.t
  | Not_jpeg of string
  | Hash of string
  | Read_original of Cap_error.t
  | Write_preview of Cap_error.t
  | Store of Db.error

let error_to_string = function
  | Decode e -> "decode: " ^ Cap_error.to_string e
  | Encode e -> "encode: " ^ Cap_error.to_string e
  | Not_jpeg type' -> "encode: the WebView produced " ^ type' ^ ", not JPEG"
  | Hash m -> "sha256: " ^ m
  | Read_original e -> "reading the original: " ^ Cap_error.to_string e
  | Write_preview e -> "writing the preview: " ^ Cap_error.to_string e
  | Store e -> "store: " ^ Db.error_to_string e

type t = {jpeg : Brr.Blob.t; width : int; height : int}

let map_error f fut = Fut.map (Result.map_error f) fut
let mime = "image/jpeg"

let encode canvas =
  Fut.map
    (function
      | Ok blob ->
          let type' = Jstr.to_string (Brr.Blob.type' blob) in
          if String.equal type' mime then Ok blob else Error (Not_jpeg type')
      | Error e -> Error (Encode e))
    (Herbier_bindings.Canvas_blob.to_blob canvas ~type':mime
       ~quality:Preview_size.quality)

(* White under the image: JPEG has no alpha, and the encoder composites
   transparent pixels onto black. The default smoothing ("low") is bilinear
   without mipmaps, which aliases fine detail on a large downscale. *)
let draw bitmap =
  let width, height =
    Preview_size.fit
      ~width:(Image_bitmap.width bitmap)
      ~height:(Image_bitmap.height bitmap)
  in
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
  | canvas -> Ok (canvas, width, height)
  | exception Jv.Error e -> Error (Encode (Cap_error.of_jv_error e))

let make original =
  let open Fut.Result_syntax in
  let* bitmap = map_error (fun e -> Decode e) (Image_bitmap.of_blob original) in
  let* canvas, width, height = Fut.return (draw bitmap) in
  let+ jpeg = encode canvas in
  {jpeg; width; height}

let sha256_hex blob =
  let open Fut.Result_syntax in
  let* buffer =
    map_error
      (fun e -> Read_original (Cap_error.of_jv_error e))
      (Brr.Blob.array_buffer blob)
  in
  let subtle = Brr_webcrypto.Crypto.subtle Brr_webcrypto.Crypto.crypto in
  let algo = Brr_webcrypto.Crypto_algo.v Brr_webcrypto.Crypto_algo.sha_256 in
  Fut.map
    (function
      | Ok digest ->
          Ok
            (Jstr.to_string
               (Brr.Tarray.to_hex_jstr
                  (Brr.Tarray.of_buffer Brr.Tarray.Uint8 digest)))
      | Error e -> Error (Hash (Jstr.to_string (Jv.Error.message e))))
    (Brr_webcrypto.Subtle_crypto.digest subtle algo
       (Brr.Tarray.of_buffer Brr.Tarray.Uint8 buffer))

let photo ~id ~observation_id ~taken_at ~original_target ~sha256 (p : t) =
  let now = Ptime_clock.now () in
  {
    Photo.id;
    observation_id;
    taken_at;
    width = p.width;
    height = p.height;
    sha256;
    preview_path = Files.preview id;
    preview_bucket_key = None;
    original_target;
    drive_file_id = None;
    upload_state = Photo.Upload_state.Pending;
    created_at = now;
    updated_at = now;
    deleted_at = None;
  }

(* Best effort: a failed delete leaves an orphan preview, which no row points
   to. *)
let delete_then path error =
  Fut.map
    (fun (_ : (unit, Cap_error.t) result) -> Error error)
    (Files.delete ~path)

let write db photo (preview : t) =
  Fut.bind (Files.write_blob ~path:photo.Photo.preview_path preview.jpeg)
    (function
    | Error e -> delete_then photo.preview_path (Write_preview e)
    | Ok () ->
        Fut.bind
          (Db.edit db [Herbier_store.Photos.upsert photo])
          (function
            | Ok (_ : int) -> Fut.return (Ok photo)
            | Error e -> delete_then photo.preview_path (Store e)))

let save db ?preview ~observation_id ~taken_at ~original_target original =
  let open Fut.Result_syntax in
  let* sha256 = sha256_hex original in
  let* preview =
    match preview with Some p -> Fut.ok p | None -> make original
  in
  let id = Photo_id.fresh () in
  write db
    (photo ~id ~observation_id ~taken_at ~original_target ~sha256 preview)
    preview
