open Brr

(* Created at startup by [mount]: a live region must exist, empty, before a
   text arrives in it for a screen reader to announce that text. *)
let region =
  lazy
    (let el =
       El.div
         ~at:
           [
             At.class' (Jstr.v "toast-region");
             At.v (Jstr.v "role") (Jstr.v "status");
             At.v (Jstr.v "aria-live") (Jstr.v "polite");
           ]
         []
     in
     El.append_children (Document.body G.document) [el];
     el)

let mount () = ignore (Lazy.force region : El.t)

let show ~ms text =
  let el =
    El.p
      ~at:
        [
          At.class' (Jstr.v "toast");
          At.style (Jstr.v (Printf.sprintf "--toast-ms: %dms" ms));
        ]
      [El.txt' text]
  in
  El.append_children (Lazy.force region) [el];
  let timer = G.set_timeout ~ms (fun () -> El.remove el) in
  Rb.on_release (fun () ->
      G.stop_timer timer;
      El.remove el)
