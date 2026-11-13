open Brr
module RList = ReactiveData.RList

let button label = El.button [El.txt' label]

let check log label ok =
  Kit.append log (Printf.sprintf "%s: %s" label (if ok then "ok" else "FAIL"))

(* A row without bindings of its own. *)
let static s = (El.li [El.txt' s], [])
let text_of node = Jv.to_string (Jv.get (El.to_jv node) "textContent")
let texts el = List.map text_of (El.children el)

(* The signal bindings, on a detached element driven by primitives that
   release does not touch, so a frozen DOM shows the stop itself. *)
let check_signals log =
  let el = El.div [] and box = El.div [] in
  let n, set_n = React.S.create 1 in
  let bindings =
    [
      Rb.text el (React.S.map string_of_int n);
      Rb.class_ box "on" (React.S.map (fun n -> n > 1) n);
      Rb.attr box "data-n" (React.S.map (fun n -> Some (string_of_int n)) n);
      Rb.style box "order"
        (React.S.map (function 1 -> "" | n -> string_of_int n) n);
      Rb.children box
        (React.S.map ~eq:( == ) (fun n -> List.init n (fun _ -> El.span [])) n);
    ]
  in
  let state () =
    ( text_of el,
      El.class' (Jstr.v "on") box,
      Option.map Jstr.to_string (El.at (Jstr.v "data-n") box),
      Jstr.to_string (El.inline_style (Jstr.v "order") box),
      List.length (El.children box) )
  in
  let start = state () in
  set_n 2;
  check log "text, class_, attr, style, children follow their signal"
    (start = ("1", false, Some "1", "", 1)
    && state () = ("2", true, Some "2", "2", 2));
  Rb.release bindings;
  set_n 3;
  check log "release freezes them while the source moves"
    (state () = ("2", true, Some "2", "2", 2))

let check_rlist log =
  let l, h = RList.create ["a"; "b"; "c"] in
  let ul = El.ul [] in
  let b = Rb.rlist ul static l in
  let synced () = texts ul = RList.value l in
  let node_of s = List.find_opt (fun n -> text_of n = s) (El.children ul) in
  let c = node_of "c" in
  let steps =
    [
      ("snoc", fun () -> RList.snoc "d" h);
      ("cons", fun () -> RList.cons "z" h);
      ("insert at 1", fun () -> RList.insert "y" 1 h);
      ("remove 1", fun () -> RList.remove 1 h);
      ("update 0", fun () -> RList.update "z'" 0 h);
      ("move 0 by +2", fun () -> RList.move 0 2 h);
      ( "move last by -1",
        fun () -> RList.move (List.length (RList.value l) - 1) (-1) h );
    ]
  in
  List.iter
    (fun (label, step) ->
      step ();
      check log
        ("rlist " ^ label ^ " patches in place")
        (synced () && c <> None && node_of "c" = c))
    steps;
  RList.set h ["p"; "q"];
  check log "rlist set rebuilds" (synced ());
  Rb.release [b]

let check_rev log =
  let l, h = RList.create ["a"; "b"; "c"] in
  let ul = El.ul [] in
  let b = Rb.rlist ul static (RList.rev l) in
  RList.snoc "d" h;
  RList.update "b'" 1 h;
  RList.move 0 2 h;
  RList.remove 0 h;
  check log "rlist over RList.rev (negative indices)"
    (texts ul = List.rev (RList.value l));
  Rb.release [b]

let check_text_rows log =
  let l, h = RList.create ["a"; "b"] in
  let el = El.div [] in
  let b = Rb.rlist el (fun s -> (El.txt' s, [])) l in
  RList.cons "z" h;
  RList.insert "y" 2 h;
  check log "rlist with text-node rows" (texts el = RList.value l);
  Rb.release [b]

let check_drift log =
  let l, h = RList.create ["a"; "b"] in
  let ul = El.ul [] in
  let b = Rb.rlist ul static l in
  El.set_children ul [];
  RList.remove 1 h;
  check log "rlist rebuilds after foreign changes (console warning)"
    (texts ul = ["a"]);
  Rb.release [b]

let check_anchor log =
  let row = static in
  let loose, loose_h = RList.create ["a"] in
  Rb.release [Rb.rlist (El.ul []) row loose];
  RList.snoc "b" loose_h;
  check log "an unanchored list stops with its only binding"
    (RList.value loose = ["a"]);
  let kept, kept_h = RList.create ["a"] in
  let _anchor = Rb.anchor_list kept in
  Rb.release [Rb.rlist (El.ul []) row kept];
  RList.snoc "b" kept_h;
  let ul = El.ul [] in
  let b = Rb.rlist ul row kept in
  RList.snoc "c" kept_h;
  check log "an anchored list outlives its binding and binds again"
    (RList.value kept = ["a"; "b"; "c"] && texts ul = ["a"; "b"; "c"]);
  Rb.release [b]

(* Each row holds one binding of its own: [Rb.live] counts the rows, and a
   removed or replaced row stops following its source. *)
let check_item_bindings log =
  let on, set_on = React.S.create false in
  let l, h = RList.create ["a"; "b"] in
  let ul = El.ul [] in
  let row s =
    let li = El.li [El.txt' s] in
    (li, [Rb.class_ li "on" on])
  in
  let base = Rb.live () in
  let b = Rb.rlist ul row l in
  let rows () = Rb.live () - base - 1 in
  let first = List.hd (El.children ul) in
  RList.snoc "c" h;
  let added = rows () = 3 in
  RList.remove 0 h;
  RList.update "b'" 0 h;
  let removed = rows () = 2 in
  set_on true;
  let on_class n = El.class' (Jstr.v "on") n in
  check log "rlist items' bindings follow their rows"
    (added
    && removed
    && (not (on_class first))
    && List.for_all on_class (El.children ul));
  Rb.release [b];
  check log "releasing the rlist releases its items' bindings"
    (Rb.live () = base)

let self_check () =
  let log = El.div [El.h2 [El.txt' "Self-check"]] in
  List.iter
    (fun run -> run log)
    [
      check_signals;
      check_rlist;
      check_rev;
      check_text_rows;
      check_drift;
      check_anchor;
      check_item_bindings;
    ];
  Kit.append log "done";
  log

let el () =
  let plus = button "+1" and toggle = button "toggle" in
  let add = button "add row" and drop = button "remove first" in
  let rename = button "update first" and swap = button "move first down" in
  let stop = button "release display" in
  let stop_sources = button "release sources" in
  let poke = button "act" and poke_release = button "act then release" in
  let live_el = El.span ~at:[At.id (Jstr.v "live")] [] in
  let acted_el = El.span ~at:[At.id (Jstr.v "acted")] [El.txt' "0"] in
  let show_live () =
    El.set_children live_el [El.txt' (string_of_int (Rb.live ()))]
  in
  let count_el = El.span ~at:[At.id (Jstr.v "count")] [] in
  let dots = El.span ~at:[At.id (Jstr.v "dots")] [] in
  let state = El.span ~at:[At.id (Jstr.v "state")] [] in
  let box = El.div ~at:[At.id (Jstr.v "box")] [state] in
  let rows = El.ul ~at:[At.id (Jstr.v "rows")] [] in
  let source = El.p ~at:[At.id (Jstr.v "source")] [] in
  let plus_clicks, b1 = Rb.ev plus Ev.click in
  let toggle_clicks, b2 = Rb.ev toggle Ev.click in
  let count = React.S.accum (React.E.map (fun _ n -> n + 1) plus_clicks) 0 in
  let on = React.S.accum (React.E.map (fun _ b -> not b) toggle_clicks) false in
  let list, handle = RList.create ["a"; "b"] in
  let next = ref 0 in
  (* Each row holds a binding of its own, so that adding, removing, updating
     and releasing rows moves [Rb.live]. *)
  let row s =
    let li = El.li [El.txt' s] in
    (li, [Rb.class_ li "on" on])
  in
  let pokes, send_poke = React.E.create () in
  (* style: [acted] counts the calls of the [Rb.act] handler, from that
     handler only. *)
  let acted = ref 0 in
  let act =
    Rb.act pokes (fun () ->
        incr acted;
        El.set_children acted_el [El.txt' (string_of_int !acted)];
        show_live ())
  in
  let listen b f =
    Ev.listen Ev.click
      (fun _ ->
        f ();
        show_live ())
      (El.as_target b)
  in
  let row_buttons =
    [
      listen add (fun () ->
          incr next;
          RList.snoc (Printf.sprintf "row %d" !next) handle);
      listen drop (fun () ->
          match RList.value list with [] -> () | _ -> RList.remove 0 handle);
      listen rename (fun () ->
          match RList.value list with
          | [] -> ()
          | first :: _ -> RList.update (first ^ "'") 0 handle);
      listen swap (fun () ->
          match RList.value list with
          | _ :: _ :: _ -> RList.move 0 1 handle
          | _ -> ());
      listen poke (fun () -> send_poke ());
      (* The queued occurrence must be dropped: the release comes first. *)
      listen poke_release (fun () ->
          send_poke ();
          Rb.release [act]);
    ]
  in
  let sources =
    [
      b1;
      b2;
      Rb.text source
        (React.S.l3
           (fun n on rows ->
             Printf.sprintf "source: count %d, %s, rows [%s]" n
               (if on then "on" else "off")
               (String.concat "; " rows))
           count on (RList.signal list));
    ]
  in
  let bindings =
    [
      Rb.text count_el (React.S.map string_of_int count);
      Rb.children dots
        (React.S.map ~eq:( == )
           (fun n -> List.init (n mod 4) (fun _ -> El.txt' "•"))
           count);
      Rb.text state (React.S.map (fun on -> if on then "on" else "off") on);
      Rb.class_ box "on" on;
      Rb.attr box "data-on"
        (React.S.map (fun on -> if on then Some "yes" else None) on);
      Rb.style box "font-weight"
        (React.S.map (fun on -> if on then "bold" else "") on);
      Rb.rlist rows row list;
      act;
    ]
  in
  (* The two release buttons' listeners are what hold the bindings: a
     binding nobody holds may be collected (Rb). *)
  let on_click b f =
    ignore (Ev.listen Ev.click (fun _ -> f ()) (El.as_target b) : Ev.listener)
  in
  on_click stop (fun () ->
      Rb.release bindings;
      show_live ());
  on_click stop_sources (fun () ->
      Rb.release sources;
      List.iter Ev.unlisten row_buttons;
      show_live ());
  (* Once the router has also built the shell, whose bindings count too. *)
  Fut.await (Fut.return ()) show_live;
  El.div
    [
      El.h1 [El.txt' "Rb check"];
      self_check ();
      El.p [plus; El.txt' " count: "; count_el; El.txt' " "; dots];
      El.p [toggle; El.txt' " "; box];
      El.p [add; drop; rename; swap];
      rows;
      source;
      El.p [poke; poke_release; El.txt' " acted: "; acted_el];
      El.p [stop; stop_sources; El.txt' " live: "; live_el];
    ]
