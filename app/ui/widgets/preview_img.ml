open Brr

let v ?(cls = []) path =
  let img = El.img ~at:[At.v (Jstr.v "alt") Jstr.empty] () in
  let at = List.map (fun c -> At.class' (Jstr.v c)) ("preview-img" :: cls) in
  let box = El.div ~at [img] in
  let warn detail = Console.(warn [str ("preview " ^ path); str detail]) in
  Fut.await
    (Herbier_store.Files.read_blob ~path ~type':Herbier_photos.Preview.mime)
    (function
    | Error e -> warn (Herbier_bindings.Cap_error.to_string e)
    | Ok blob ->
        let url = Herbier_bindings.Object_url.create blob in
        let opts = Ev.listen_opts ~once:true () in
        let settle loaded =
          Herbier_bindings.Object_url.revoke url;
          match loaded with
          | true -> El.set_class (Jstr.v "preview-img--loaded") true box
          | false -> warn "the image did not decode"
        in
        (* The listeners go with the image: once it has loaded or failed the
           URL is no longer needed. *)
        ignore
          (Ev.listen ~opts Ev.load (fun _ -> settle true) (El.as_target img));
        ignore
          (Ev.listen ~opts Ev.error (fun _ -> settle false) (El.as_target img));
        El.set_at (Jstr.v "src") (Some url) img);
  box
