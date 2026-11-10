module Cap_camera = Herbier_bindings.Cap_camera
module Cap_error = Herbier_bindings.Cap_error
module Cap_geolocation = Herbier_bindings.Cap_geolocation
module Exifr = Herbier_bindings.Exifr
module Exif = Herbier_photos.Exif

let append log text = Brr.El.append_children log [Brr.El.div [Brr.El.txt' text]]

let button label on_click =
  let b = Brr.El.button [Brr.El.txt' label] in
  (* The listener lives as long as the page; nothing unlistens it. *)
  let _ : Brr.Ev.listener =
    Brr.Ev.listen Brr.Ev.click (fun _ -> on_click ()) (Brr.El.as_target b)
  in
  b

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

let read_exif m =
  let open Fut.Syntax in
  let* blob = Herbier_bindings.Web_path.blob m.Cap_camera.web_path in
  match blob with
  | Error e -> Fut.return ("fetch: " ^ e)
  | Ok blob -> (
      let+ r = Exifr.parse ~pick:Exif.tags blob in
      match r with
      | Ok None -> "no EXIF"
      | Ok (Some text) ->
          describe (Exif.of_string ~tz_offset_at text) ^ " · " ^ text
      | Error e -> Cap_error.to_string e)

let pick log () =
  Fut.await (Cap_camera.choose_photos ~limit:5) (function
    | Error e -> append log ("pick: " ^ Cap_error.to_string e)
    | Ok media ->
        List.iter
          (fun (m : Cap_camera.media) ->
            Fut.await (read_exif m) (fun line ->
                append log (m.web_path ^ ": " ^ line)))
          media)

let locate log () =
  Fut.await
    (Cap_geolocation.current_position ~high_accuracy:true ~timeout_ms:20_000
       ~maximum_age_ms:0) (function
    | Ok p ->
        append log
          (Printf.sprintf "gps: %.6f,%.6f ±%.0f m" p.latitude p.longitude
             p.accuracy_m)
    | Error e -> append log ("gps: " ^ Cap_error.to_string e))

let el () =
  let log = Brr.El.div ~at:[Brr.At.v (Jstr.v "role") (Jstr.v "log")] [] in
  Brr.El.div
    [
      Brr.El.h1 [Brr.El.txt' "Photo check"];
      button "Pick photos" (pick log);
      button "GPS position" (locate log);
      log;
    ]
