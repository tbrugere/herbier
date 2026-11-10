open Brr
module Db = Herbier_store.Db

let el () =
  let root = El.div [El.p [El.txt' "opening herbier…"]] in
  Fut.await (Db.open_ ~database:"herbier") (function
    | Error e ->
        El.set_children root [El.p [El.txt' ("open: " ^ Db.error_to_string e)]]
    | Ok db ->
        let screen = Screens.Collection.v ~db ~state:(Fixture.state ()) in
        (* The page is left by a reload: nothing releases the screen, so its
           bindings are held by the page's root. *)
        Rb.hold root screen.bindings;
        El.set_children root [screen.el]);
  root
