open Brr

let root () =
  match Document.find_el_by_id G.document (Jstr.v "app") with
  | Some root -> root
  | None ->
      let root = El.div [] in
      El.append_children (Document.body G.document) [root];
      root

let () =
  Herbier_ui.Router.start ~root:(root ()) ~tab:Herbier_ui.Screens.Placeholder.v
    ~dev:Dev_pages.find
