open Brr
module RList = ReactiveData.RList

type node =
  | Signal : unit React.signal -> node
  | Event : 'a React.event -> node
  | Listener : Ev.listener * 'a React.event -> node
  | List_items : unit React.event * (El.t * binding list) array ref -> node

(* style: [live] is mutated by [release] only and makes a double release
   harmless. [count] is a global counter because the leak check needs the
   number of unreleased bindings over the whole app: [make] increments it,
   [release] decrements it once per binding thanks to [live]. *)
and binding = {node : node; mutable live : bool}

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

let rec stop = function
  | Signal s -> React.S.stop ~strong:true s
  | Event e -> React.E.stop ~strong:true e
  | Listener (l, e) ->
      Ev.unlisten l;
      React.E.stop ~strong:true e
  | List_items (e, items) ->
      React.E.stop ~strong:true e;
      release_all !items;
      items := [||]

and release bs =
  List.iter
    (fun b ->
      match b.live with
      | false -> ()
      | true ->
          stop b.node;
          b.live <- false;
          decr count)
    bs

and release_all items = Array.iter (fun (_, bs) -> release bs) items

let insert_at a i x =
  Array.concat [Array.sub a 0 i; [|x|]; Array.sub a i (Array.length a - i)]

let remove_at a i =
  Array.append (Array.sub a 0 i) (Array.sub a (i + 1) (Array.length a - i - 1))

(* The children of an [rlist] container, each with its own bindings, in
   order. [apply_step] applies a step to the DOM and returns the updated
   children (a new array; the argument is untouched), or [None] when the
   step's index is out of range; ReactiveData counts a negative index from the
   end ([I (-1, _)] appends). *)
let apply_step el f items step =
  let n = Array.length items in
  let at i = if i < 0 then n + i else i in
  let valid i = i >= 0 && i < n in
  match step with
  | RList.I (i, v) -> (
      match if i < 0 then n + 1 + i else i with
      | i when i >= 0 && i <= n ->
          let ((node, _) as x) = f v in
          if i = n then El.append_children el [node]
          else El.insert_siblings `Before (fst items.(i)) [node];
          Some (insert_at items i x)
      | _ -> None)
  | RList.R i -> (
      match at i with
      | i when valid i ->
          let node, bs = items.(i) in
          El.remove node;
          release bs;
          Some (remove_at items i)
      | _ -> None)
  | RList.U (i, v) -> (
      match at i with
      | i when valid i ->
          let node, bs = items.(i) in
          let ((node', _) as x) = f v in
          El.insert_siblings `Replace node [node'];
          release bs;
          let items = Array.copy items in
          items.(i) <- x;
          Some items
      | _ -> None)
  | RList.X (i, 0) -> if valid (at i) then Some items else None
  | RList.X (i, offset) -> (
      match (at i, at i + offset) with
      | i, j when valid i && valid j ->
          let ((moved, _) as x) = items.(i) in
          let target = fst items.(j) in
          El.remove moved;
          if offset > 0 then El.insert_siblings `After target [moved]
          else El.insert_siblings `Before target [moved];
          Some (insert_at (remove_at items i) j x)
      | _ -> None)

(* Whether [el]'s child nodes are still exactly the tracked children, in
   order: something else may have added or removed some. *)
let in_step el items =
  let kids = Array.of_list (El.children el) in
  Array.length kids = Array.length items
  && Array.for_all2
       (fun k (node, _) -> Jv.strict_equal (El.to_jv k) (El.to_jv node))
       kids items

let rlist el f l =
  (* style: [items] is the container's model, written once per [Patch] (after
     all its steps, or, when a step fails, to the children so far, then by
     [rebuild]), by [rebuild] at construction and on [Set], and cleared on
     release. *)
  let items = ref [||] in
  let rebuild () =
    release_all !items;
    let fresh = Array.of_list (List.map f (RList.value l)) in
    El.set_children el (Array.to_list (Array.map fst fresh));
    items := fresh
  in
  let resync () =
    Console.(
      warn [str "Rb.rlist: child nodes out of step with the list, rebuilding"]);
    rebuild ()
  in
  rebuild ();
  let e =
    React.E.map
      (function
        | RList.Set _ -> rebuild ()
        | RList.Patch _ when not (in_step el !items) -> resync ()
        | RList.Patch steps -> (
            (* [Error last]: the children after the last step that applied,
               so that [rebuild] releases the items earlier steps created. *)
            let step acc s =
              match acc with
              | Error _ -> acc
              | Ok items -> (
                  match apply_step el f items s with
                  | Some next -> Ok next
                  | None -> Error items)
            in
            match List.fold_left step (Ok !items) steps with
            | Ok next -> items := next
            | Error last ->
                items := last;
                resync ()))
      (RList.event l)
  in
  make (List_items (e, items))

let ev el type' =
  let e, send = React.E.create () in
  let listener = Ev.listen type' send (El.as_target el) in
  (e, make (Listener (listener, e)))

let click el =
  let e, b = ev el Ev.click in
  (React.E.map (fun _ -> ()) e, b)

let on e f = make (Event (React.E.map f e))

let act e f =
  (* style: [self] is read by the queued callback to drop occurrences that
     arrive after a release. *)
  let self = ref None in
  let run v =
    match !self with
    | Some {live = true; _} -> f v
    | Some {live = false; _} | None -> ()
  in
  let b = on e (fun v -> Fut.await (Fut.ok ()) (fun _ -> run v)) in
  self := Some b;
  b

let hold el bs = Herbier_bindings.Keep.on el bs

type anchor = Anchor : 'a React.event -> anchor

let anchor s = Anchor (React.S.changes s)
let anchor_list l = Anchor (React.E.map ignore (RList.event l))
