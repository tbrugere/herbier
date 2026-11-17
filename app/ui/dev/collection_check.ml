open Brr
module Db = Herbier_store_io.Db

let el db =
  match db with
  | Error e -> El.p [El.txt' ("no herbier database: " ^ e)]
  | Ok db ->
      let screen =
        Screens.Collection.v
          (App.create ~db ~state:(Fixture.state ()) ~theme:(Theme.load ())
             ~auth:(Fixture.auth ()) ~identification:Fixture.identification)
      in
      let root = El.div [screen.el] in
      (* The page is left by a reload: nothing releases the screen, so its
         bindings are held by the page's root. *)
      Rb.hold root screen.bindings;
      root
