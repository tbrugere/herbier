type t = {id : int; close : unit -> unit}

(* style: module state because the overlays are opened by screens long after
   the router registered its back listener; single JS thread. *)
let stack = ref []
let next = ref 0

let push ~close =
  incr next;
  let t = {id = !next; close} in
  stack := t :: !stack;
  t

let remove t = stack := List.filter (fun o -> o.id <> t.id) !stack

let close_top () =
  match !stack with
  | [] -> false
  | top :: rest -> (
      stack := rest;
      match top.close () with
      | () -> true
      | exception ((Out_of_memory | Stack_overflow) as e) -> raise e
      | exception e ->
          Log.error ~scope:"overlay" "close failed" (Printexc.to_string e);
          true)
