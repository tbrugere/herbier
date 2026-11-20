type t = {
  id : int;
  surface : Herbier_ui_model.System_bars.surface;
  close : unit -> unit;
}

(* style: module state because the overlays are opened by screens long after
   the router registered its back listener; single JS thread. *)
let stack = ref []
let next = ref 0

(* style: module state, as [stack]: System_bars registers once at startup. *)
let observer = ref (fun () -> ())
let on_change f = observer := f

(* A raise here would leave the stack changed but the overlay not closed, or
   escape a screen's release. *)
let notify () =
  match !observer () with
  | () -> ()
  | exception ((Out_of_memory | Stack_overflow) as e) -> raise e
  | exception e ->
      Log.error ~scope:"overlay" "observer failed" (Printexc.to_string e)

let push ~surface ~close =
  incr next;
  let t = {id = !next; surface; close} in
  stack := t :: !stack;
  notify ();
  t

let remove t =
  match List.exists (fun o -> o.id = t.id) !stack with
  | false -> ()
  | true ->
      stack := List.filter (fun o -> o.id <> t.id) !stack;
      notify ()

let surfaces () = List.map (fun o -> o.surface) !stack

let close_top () =
  match !stack with
  | [] -> false
  | top :: rest -> (
      stack := rest;
      notify ();
      match top.close () with
      | () -> true
      | exception ((Out_of_memory | Stack_overflow) as e) -> raise e
      | exception e ->
          Log.error ~scope:"overlay" "close failed" (Printexc.to_string e);
          true)
