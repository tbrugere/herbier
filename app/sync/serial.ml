(* style: mutable field because each [run] chains on the step started
   before it, from future callbacks; nothing outside this module sees it. *)
type t = {mutable last : unit Fut.t}

let create () = {last = Fut.return ()}

let run t step =
  let result = Fut.bind t.last step in
  t.last <- Fut.map ignore result;
  result
