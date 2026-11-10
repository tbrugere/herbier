open Brr
module Db = Herbier_store.Db

let el () =
  let root = El.div [El.p [El.txt' "opening herbier…"]] in
  Fut.await (Db.open_ ~database:"herbier") (function
    | Error e ->
        El.set_children root [El.p [El.txt' ("open: " ^ Db.error_to_string e)]]
    | Ok db ->
        let state =
          State.create
            ~network:{online = true; pending_uploads = 0}
            ~account:
              {
                google_signed_in = false;
                storage = Herbier_domain.Photo.Original_target.App_only;
              }
        in
        let screen = Screens.Collection.v ~db ~state in
        (* The page is left by a reload: nothing releases the screen, so its
           bindings are held by the page's root. *)
        Rb.hold root screen.bindings;
        El.set_children root [screen.el]);
  root
