open Brr

let title () = El.h1 ~at:At.[class' (Jstr.v "title")] [El.txt' "Herbier"]

let mount el =
  match Document.find_el_by_id G.document (Jstr.v "app") with
  | Some root -> El.set_children root [el]
  | None -> El.append_children (Document.body G.document) [el]

(* Read once at startup: the dev page is reached by reloading with the
   fragment set. *)
let () =
  match Jstr.to_string (Uri.fragment (Window.location G.window)) with
  | "dev/storage" -> mount (Herbier_ui.Dev.Storage_check.el ())
  | "dev/store" -> mount (Herbier_ui.Dev.Store_check.el ())
  | "dev/seed" -> mount (Herbier_ui.Dev.Seed_check.el ())
  | "dev/refs-http" -> mount (Herbier_ui.Dev.Refs_http_check.el ())
  | _ -> mount (title ())
