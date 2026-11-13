module Exif = Herbier_photos.Exif
module Cap_error = Herbier_bindings.Cap_error
module Cap_camera = Herbier_bindings.Cap_camera
module Camera_stream = Herbier_bindings.Camera_stream
module Exifr = Herbier_bindings.Exifr
module Fut_result = Herbier_bindings.Fut_result

type source = Shutter | Gallery

type shot = {
  original : Brr.Blob.t;
  source : source;
  exif : Exif.t;
  preview : Preview.t;
}

type error =
  | Camera of Cap_error.t
  | Stopped
  | Pick of Cap_error.t
  | Fetch of string
  | Preview of Preview.error

let error_to_string = function
  | Camera e -> "camera: " ^ Cap_error.to_string e
  | Stopped -> "camera: stopped"
  | Pick e -> "gallery: " ^ Cap_error.to_string e
  | Fetch m -> "gallery file: " ^ m
  | Preview e -> "preview: " ^ Preview.error_to_string e

let shot ~source ~exif original =
  Fut.map
    (Result.map (fun preview -> {original; source; exif; preview}))
    (Fut_result.map_error (fun e -> Preview e) (Preview.make original))

type viewfinder = {stream : Camera_stream.t; video : Brr.El.t}

let open_viewfinder ?facing ~video () =
  let open Fut.Result_syntax in
  let* stream =
    Fut_result.map_error (fun e -> Camera e) (Camera_stream.start ?facing ())
  in
  Camera_stream.attach stream video;
  Fut.ok {stream; video}

let frame_quality = 0.92

let still v =
  let frame () = Camera_stream.frame v.video ~quality:frame_quality in
  match Camera_stream.has_image_capture () with
  | false -> frame ()
  | true ->
      Fut.bind (Camera_stream.take_photo v.stream) (function
        | Ok b -> Fut.ok b
        | Error e ->
            Brr.Console.(
              warn
                [
                  str "capture: takePhoto failed, taking a video frame:";
                  str (Cap_error.to_string e);
                ]);
            frame ())

let shutter v =
  let open Fut.Result_syntax in
  match Camera_stream.live v.stream with
  | false -> Fut.error Stopped
  | true ->
      let* original = Fut_result.map_error (fun e -> Camera e) (still v) in
      shot ~source:Shutter ~exif:Exif.empty original

let close_viewfinder v = Camera_stream.stop v.stream

let tz_offset_at (year, month, day) (hour, minute, second) =
  Herbier_bindings.Js_date.local_offset_s ~year ~month ~day ~hour ~minute
    ~second

let exif_of blob =
  Fut.map
    (function
      | Ok (Some text) -> Exif.of_string ~tz_offset_at text
      | Ok None | Error _ -> Exif.empty)
    (Exifr.parse ~pick:Exif.tags blob)

let picked (m : Cap_camera.media) =
  let open Fut.Result_syntax in
  let* original =
    Fut_result.map_error
      (fun m -> Fetch m)
      (Herbier_bindings.Web_path.blob m.web_path)
  in
  Fut.bind (exif_of original) (fun exif -> shot ~source:Gallery ~exif original)

let pick ~limit =
  let open Fut.Result_syntax in
  let* media =
    Fut_result.map_error (fun e -> Pick e) (Cap_camera.choose_photos ~limit)
  in
  (* One at a time: each decode holds a full-size bitmap. *)
  Fut_result.traverse picked media
