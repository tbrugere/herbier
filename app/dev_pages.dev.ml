open Brr

(* Dev pages manage their own bindings (the router reloads the page when one
   is left), so they hand the router none. *)
let page el () =
  {
    Herbier_ui.Screen.el = El.div ~at:[At.class' (Jstr.v "dev-page")] [el ()];
    bindings = [];
  }

let () = Herbier_ui.Dev.Hooks.install ()

let find db =
  let module D = Herbier_ui.Dev in
  function
  | "storage" -> Some (page D.Storage_check.el)
  | "store" -> Some (page D.Store_check.el)
  | "seed" -> Some (page (fun () -> D.Seed_check.el db))
  | "refs-http" -> Some (page D.Refs_http_check.el)
  | "photos" -> Some (page D.Photo_check.el)
  | "rb" -> Some (page D.Rb_check.el)
  | "theme" -> Some (page D.Theme_check.el)
  | "gallery" -> Some (page D.Gallery.el)
  | "collection" -> Some (page (fun () -> D.Collection_check.el db))
  | "sheet" -> Some (page D.Sheet_check.el)
  | "spike" -> Some (page (fun () -> D.Spike_check.el db))
  | _ -> None
