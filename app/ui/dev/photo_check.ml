module Cap_camera = Herbier_bindings.Cap_camera
module Cap_error = Herbier_bindings.Cap_error
module Cap_geolocation = Herbier_bindings.Cap_geolocation
module Exifr = Herbier_bindings.Exifr
module Exif = Herbier_photos.Exif
module Preview = Herbier_photos_io.Preview
module Files = Herbier_store_io.Files
module Js_error = Herbier_bindings.Js_error
module Fut_result = Herbier_bindings.Fut_result

let describe (e : Exif.t) =
  let time =
    match e.taken_at with
    | Some t -> Format.asprintf "%a" (Ptime.pp_rfc3339 ~frac_s:3 ()) t
    | None -> "no date"
  in
  let place =
    match e.position with
    | Some {lat; lon; accuracy_m = Some a} ->
        Printf.sprintf "%.6f,%.6f ±%.0f m" lat lon a
    | Some {lat; lon; accuracy_m = None} -> Printf.sprintf "%.6f,%.6f" lat lon
    | None -> "no position"
  in
  time ^ " · " ^ place

let tz_offset_at (year, month, day) (hour, minute, second) =
  Herbier_bindings.Js_date.local_offset_s ~year ~month ~day ~hour ~minute
    ~second

let read_exif blob =
  let open Fut.Syntax in
  let+ r = Exifr.parse ~pick:Exif.tags blob in
  match r with
  | Ok None -> "no EXIF"
  | Ok (Some text) ->
      describe (Exif.of_string ~tz_offset_at text) ^ " · " ^ text
  | Error e -> Cap_error.to_string e

(* Dev scratch file, outside previews/: no row points to it. *)
let preview_path = "dev/preview.jpg"
let preview fut = Fut_result.map_error Preview.error_to_string fut
let file fut = Fut_result.map_error Cap_error.to_string fut

let bytes blob =
  Fut.map
    (Result.map (fun buffer ->
         Brr.Tarray.to_string (Brr.Tarray.of_buffer Brr.Tarray.Uint8 buffer)))
    (Brr.Blob.array_buffer blob)

let show log blob =
  let url = Herbier_bindings.Object_url.create blob in
  let img =
    Brr.El.img
      ~at:
        [
          Brr.At.src url;
          Brr.At.width 200;
          Brr.At.v (Jstr.v "alt") (Jstr.v "Aperçu relu");
        ]
      ()
  in
  let _ : Brr.Ev.listener =
    Brr.Ev.listen Brr.Ev.load
      (fun _ -> Herbier_bindings.Object_url.revoke url)
      (Brr.El.as_target img)
  in
  Brr.El.append_children log [img]

let check_preview log original =
  let open Fut.Result_syntax in
  let* sha = preview (Preview.sha256_hex original) in
  let* p = preview (Preview.make original) in
  let* () = file (Files.write_blob ~path:preview_path p.jpeg) in
  let* back = file (Files.read_blob ~path:preview_path ~type':Preview.mime) in
  let+ back_bytes = Fut_result.map_error Js_error.message (bytes back) in
  let written = Brr.Blob.byte_length p.jpeg in
  let read = Brr.Blob.byte_length back in
  Kit.append log
    (Printf.sprintf
       "preview %dx%d, %d bytes written, %d read back (%s), EXIF segment: %s, \
        original sha256 %s"
       p.width p.height written read
       (match written = read with
       | true -> "round-trip ok"
       | false -> "MISMATCH")
       (match Herbier_photos.Jpeg.has_exif back_bytes with
       | true -> "PRESENT"
       | false -> "none")
       sha);
  show log back

(* One photo at a time: each decodes its full-resolution original, and all
   share the scratch file. *)
let check log (m : Cap_camera.media) =
  let open Fut.Syntax in
  let* blob = Herbier_bindings.Web_path.blob m.web_path in
  match blob with
  | Error e ->
      Kit.append log (m.web_path ^ ": fetch: " ^ e);
      Fut.return ()
  | Ok blob ->
      let* line = read_exif blob in
      Kit.append log (m.web_path ^ ": " ^ line);
      let+ r = check_preview log blob in
      Result.iter_error (fun e -> Kit.append log ("preview: " ^ e)) r

let pick log () =
  Fut.await (Cap_camera.choose_photos ~limit:5) (function
    | Error e -> Kit.append log ("pick: " ^ Cap_error.to_string e)
    | Ok media ->
        Fut.await
          (List.fold_left
             (fun previous m -> Fut.bind previous (fun () -> check log m))
             (Fut.return ()) media)
          Fun.id)

let locate log () =
  Fut.await
    (Cap_geolocation.current_position ~high_accuracy:true ~timeout_ms:20_000
       ~maximum_age_ms:0) (function
    | Ok p ->
        Kit.append log
          (Printf.sprintf "gps: %.6f,%.6f ±%.0f m" p.latitude p.longitude
             p.accuracy_m)
    | Error e -> Kit.append log ("gps: " ^ Cap_error.to_string e))

let el () =
  let log = Brr.El.div ~at:[Brr.At.v (Jstr.v "role") (Jstr.v "log")] [] in
  Brr.El.div
    [
      Brr.El.h1 [Brr.El.txt' "Photo check"];
      Kit.action "Pick photos" (pick log);
      Kit.action "GPS position" (locate log);
      log;
    ]
