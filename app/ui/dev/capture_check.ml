open Brr
module Capture = Herbier_photos.Capture
module Files = Herbier_store.Files
module Cap_error = Herbier_bindings.Cap_error

let append log text = El.append_children log [El.div [El.txt' text]]

let button label f =
  let b = El.button [El.txt' label] in
  ignore (Ev.listen Ev.click (fun _ -> f ()) (El.as_target b));
  b

type camera = Off | Opening | On of Capture.viewfinder

let show log count (s : Capture.shot) =
  incr count;
  let path = Printf.sprintf "dev/capture-%d.jpg" !count in
  let open Fut.Result_syntax in
  let fut =
    let* () = Files.write_blob ~path s.preview.jpeg in
    let* back = Files.read_blob ~path ~type':"image/jpeg" in
    let+ uri =
      Fut.map
        (Result.map_error (fun e ->
             Cap_error.Rejected
               {code = None; message = Jstr.to_string (Jv.Error.message e)}))
        (Blob.data_uri back)
    in
    (back, uri)
  in
  Fut.await fut (function
    | Error e -> append log (path ^ ": " ^ Cap_error.to_string e)
    | Ok (back, uri) ->
        append log
          (Printf.sprintf
             "%s %s: original %d bytes, preview %dx%d %d bytes, read back %d"
             (match s.source with Shutter -> "shutter" | Gallery -> "gallery")
             path
             (Blob.byte_length s.original)
             s.preview.width s.preview.height
             (Blob.byte_length s.preview.jpeg)
             (Blob.byte_length back));
        El.append_children log
          [
            El.img
              ~at:[At.src uri; At.width 160; At.v (Jstr.v "alt") (Jstr.v path)]
              ();
          ])

let el () =
  (* style: the page's state, mutated from click and future callbacks; local
     to [el] because each visit builds a fresh page. *)
  let count = ref 0 and camera = ref Off in
  let log = El.div ~at:[At.v (Jstr.v "role") (Jstr.v "log")] [] in
  let video = El.video ~at:[At.width 320] [] in
  let start () =
    match !camera with
    | Opening | On _ -> append log "viewfinder already on"
    | Off ->
        camera := Opening;
        Fut.await (Capture.open_viewfinder ~video) (fun r ->
            match (r, !camera) with
            | Error e, _ ->
                camera := Off;
                append log (Capture.error_to_string e)
            | Ok v, Opening ->
                camera := On v;
                append log "viewfinder on"
            | Ok v, (Off | On _) -> Capture.close_viewfinder v)
  in
  let shoot () =
    match !camera with
    | Off | Opening -> append log "no viewfinder"
    | On v ->
        Fut.await (Capture.shutter v) (function
          | Error e -> append log (Capture.error_to_string e)
          | Ok s -> show log count s)
  in
  let pick () =
    Fut.await (Capture.pick ~limit:5) (function
      | Error e -> append log (Capture.error_to_string e)
      | Ok shots -> List.iter (show log count) shots)
  in
  let close () =
    (match !camera with
    | On v -> Capture.close_viewfinder v
    | Off | Opening -> ());
    camera := Off;
    append log "viewfinder off"
  in
  El.div
    ~at:[At.class' (Jstr.v "dev-page")]
    [
      El.h1 [El.txt' "Capture check"];
      video;
      El.div
        [
          button "Viseur" start;
          button "Déclencher" shoot;
          button "Galerie" pick;
          button "Fermer" close;
        ];
      log;
    ]
