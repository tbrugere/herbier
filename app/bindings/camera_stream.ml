type t = Jv.t
type facing = Back | Front

let constraints facing =
  let ideal v = Jv.obj [|("ideal", v)|] in
  Jv.obj
    [|
      ("audio", Jv.false');
      ( "video",
        Jv.obj
          [|
            ( "facingMode",
              ideal
                (Jv.of_string
                   (match facing with Back -> "environment" | Front -> "user"))
            );
            ("width", ideal (Jv.of_int 4096));
            ("height", ideal (Jv.of_int 3072));
          |] );
    |]

let has_type ty v = String.equal (Jstr.to_string (Jv.typeof v)) ty

(* A DOMException's [code] is a legacy number, which Cap_call does not read:
   its [name] is what tells a refused permission from a missing camera. *)
let rejected v =
  let name =
    match has_type "object" v && Jv.is_some v with
    | false -> None
    | true -> (
        match Jv.find v "name" with
        | Some n when has_type "string" n -> Some (Jv.to_string n)
        | Some _ | None -> None)
  in
  match (Cap_call.rejected v, name) with
  | Cap_error.Rejected {code = None; message}, Some _ ->
      Cap_error.Rejected {code = name; message}
  | e, _ -> e

let not_supported message =
  Fut.return
    (Error (Cap_error.Rejected {code = Some "NotSupportedError"; message}))

(* The Web APIs called here return a promise or throw a DOMException. *)
let promise o meth args ~ok =
  match Jv.call o meth args with
  | p -> Fut.of_promise' ~ok ~error:rejected p
  | exception Jv.Error e -> Fut.return (Error (rejected (Jv.of_error e)))

let start ?(facing = Back) () =
  let devices = Jv.get (Jv.get Jv.global "navigator") "mediaDevices" in
  match Jv.is_none devices with
  | true -> not_supported "no mediaDevices"
  | false -> promise devices "getUserMedia" [|constraints facing|] ~ok:Fun.id

let attach stream video =
  let v = Brr.El.to_jv video in
  Jv.set v "srcObject" stream;
  Jv.set v "muted" Jv.true';
  Jv.set v "playsInline" Jv.true';
  let played = Jv.call v "play" [||] in
  match Jv.is_some played with
  | true -> ignore (Jv.call played "catch" [|Jv.callback ~arity:1 ignore|])
  | false -> ()

let video_tracks stream =
  Jv.to_list Fun.id (Jv.call stream "getVideoTracks" [||])

let stop stream =
  Jv.to_list Fun.id (Jv.call stream "getTracks" [||])
  |> List.iter (fun track -> ignore (Jv.call track "stop" [||]))

let live stream =
  match video_tracks stream with
  | track :: _ ->
      String.equal (Jv.Jstr.get track "readyState" |> Jstr.to_string) "live"
  | [] -> false

let has_image_capture () = Jv.is_some (Jv.get Jv.global "ImageCapture")

let take_photo stream =
  match (has_image_capture (), video_tracks stream) with
  | false, _ -> not_supported "no ImageCapture"
  | true, [] -> not_supported "no video track"
  | true, track :: _ ->
      let ic = Jv.new' (Jv.get Jv.global "ImageCapture") [|track|] in
      promise ic "takePhoto" [||] ~ok:Brr.Blob.of_jv

let frame video ~quality =
  let v = Brr.El.to_jv video in
  let w = Jv.Int.get v "videoWidth" and h = Jv.Int.get v "videoHeight" in
  match w > 0 && h > 0 with
  | false -> Fut.return (Error (Cap_error.Unexpected "videoWidth"))
  | true ->
      let canvas = Brr_canvas.Canvas.create ~w ~h [] in
      let c = Brr_canvas.C2d.get_context canvas in
      Brr_canvas.C2d.draw_image c
        (Brr_canvas.C2d.image_src_of_el video)
        ~x:0. ~y:0.;
      Canvas_blob.to_blob canvas ~type':"image/jpeg" ~quality
