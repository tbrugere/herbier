open Brr

let title () = El.h1 ~at:At.[class' (Jstr.v "title")] [El.txt' "Herbier"]

let mount el =
  match Document.find_el_by_id G.document (Jstr.v "app") with
  | Some root -> El.set_children root [el]
  | None -> El.append_children (Document.body G.document) [el]

let () = mount (title ())
