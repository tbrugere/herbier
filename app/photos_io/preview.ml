module Preview_size = Herbier_photos.Preview_size
module Photo = Herbier_domain.Photo
module Observation_id = Herbier_domain.Ids.Observation_id
module Photo_id = Herbier_domain.Ids.Photo_id
module Cap_error = Herbier_bindings.Cap_error
module Image_bitmap = Herbier_bindings.Image_bitmap
module Db = Herbier_store_io.Db
module Files = Herbier_store_io.Files
module Canvas_jpeg = Herbier_bindings.Canvas_jpeg
module Js_error = Herbier_bindings.Js_error
module Fut_result = Herbier_bindings.Fut_result

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

let mime = Canvas_jpeg.mime

let encode canvas =
  Fut_result.map_error
    (function
      | Canvas_jpeg.Encode e -> Encode e
      | Canvas_jpeg.Not_jpeg type' -> Not_jpeg type')
    (Canvas_jpeg.encode ~quality:Preview_size.quality canvas)

let draw bitmap =
  let width, height =
    Preview_size.fit
      ~width:(Image_bitmap.width bitmap)
      ~height:(Image_bitmap.height bitmap)
  in
  match Canvas_jpeg.draw ~width ~height bitmap with
  | Ok canvas -> Ok (canvas, width, height)
  | Error e -> Error (Encode e)

let make original =
  let open Fut.Result_syntax in
  let* bitmap =
    Fut_result.map_error (fun e -> Decode e) (Image_bitmap.of_blob original)
  in
  let* canvas, width, height = Fut.return (draw bitmap) in
  let+ jpeg = encode canvas in
  {jpeg; width; height}

let sha256_hex blob =
  let open Fut.Result_syntax in
  let* buffer =
    Fut_result.map_error
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
      | Error e -> Error (Hash (Js_error.message e)))
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
