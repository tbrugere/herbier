open Brr
module RList = ReactiveData.RList

type node =
  | Signal : unit React.signal -> node
  | Event : 'a React.event -> node
  | Listener : Ev.listener * 'a React.event -> node

(* style: [live] is mutated by [release] only and makes a double release
   harmless. [count] is a global counter because the leak check needs the
   number of unreleased bindings over the whole app: [make] increments it,
   [release] decrements it once per binding thanks to [live]. *)
type binding = {node : node; mutable live : bool}

let count = ref 0

let make node =
  incr count;
  {node; live = true}

let live () = !count
let write s f = make (Signal (React.S.map f s))
let text el s = write s (fun v -> El.set_children el [El.txt' v])

let attr el name s =
  let name = Jstr.v name in
  write s (fun v -> El.set_at name (Option.map Jstr.v v) el)

let class_ el name s =
  let name = Jstr.v name in
  write s (fun on -> El.set_class name on el)

let style el prop s =
  let prop = Jstr.v prop in
  write s (function
    | "" -> El.remove_inline_style prop el
    | v -> El.set_inline_style prop (Jstr.v v) el)

let children el s = write s (El.set_children el)

let insert_at a i x =
  Array.concat [Array.sub a 0 i; [|x|]; Array.sub a i (Array.length a - i)]

let remove_at a i =
  Array.append (Array.sub a 0 i) (Array.sub a (i + 1) (Array.length a - i - 1))

(* Applies one positional patch step to [el] and to [kids], its child nodes
   read once per patch and kept in step with the DOM. ReactiveData counts a
   negative index from the end ([I (-1, _)] appends). *)
let apply_step el f kids step =
  let n = Array.length !kids in
  let at i = if i < 0 then n + i else i in
  let valid i = i >= 0 && i < n in
  match step with
  | RList.I (i, v) -> (
      match if i < 0 then n + 1 + i else i with
      | i when i >= 0 && i <= n ->
          let node = f v in
          if i = n then El.append_children el [node]
          else El.insert_siblings `Before !kids.(i) [node];
          kids := insert_at !kids i node;
          true
      | _ -> false)
  | RList.R i -> (
      match at i with
      | i when valid i ->
          El.remove !kids.(i);
          kids := remove_at !kids i;
          true
      | _ -> false)
  | RList.U (i, v) -> (
      match at i with
      | i when valid i ->
          let node = f v in
          El.insert_siblings `Replace !kids.(i) [node];
          !kids.(i) <- node;
          true
      | _ -> false)
  | RList.X (i, 0) -> valid (at i)
  | RList.X (i, offset) -> (
      match (at i, at i + offset) with
      | i, j when valid i && valid j ->
          let moved = !kids.(i) in
          El.remove moved;
          if offset > 0 then El.insert_siblings `After !kids.(j) [moved]
          else El.insert_siblings `Before !kids.(j) [moved];
          kids := insert_at (remove_at !kids i) j moved;
          true
      | _ -> false)

let rlist el f l =
  let rebuild () = El.set_children el (List.map f (RList.value l)) in
  rebuild ();
  make
    (Event
       (React.E.map
          (function
            | RList.Set _ -> rebuild ()
            | RList.Patch steps ->
                let kids = ref (Array.of_list (El.children el)) in
                if not (List.for_all (apply_step el f kids) steps) then (
                  Console.(
                    warn
                      [
                        str
                          "Rb.rlist: child nodes out of step with the list, \
                           rebuilding";
                      ]);
                  rebuild ()))
          (RList.event l)))

let ev el type' =
  let e, send = React.E.create () in
  let listener = Ev.listen type' send (El.as_target el) in
  (e, make (Listener (listener, e)))

let click el =
  let e, b = ev el Ev.click in
  (React.E.map (fun _ -> ()) e, b)

let on e f = make (Event (React.E.map f e))
let hold el bs = Herbier_bindings.Keep.on el bs

let stop = function
  | Signal s -> React.S.stop ~strong:true s
  | Event e -> React.E.stop ~strong:true e
  | Listener (l, e) ->
      Ev.unlisten l;
      React.E.stop ~strong:true e

let release =
  List.iter (fun b ->
      match b.live with
      | false -> ()
      | true ->
          stop b.node;
          b.live <- false;
          decr count)

type anchor = Anchor : 'a React.event -> anchor

let anchor s = Anchor (React.S.changes s)
let anchor_list l = Anchor (React.E.map ignore (RList.event l))
