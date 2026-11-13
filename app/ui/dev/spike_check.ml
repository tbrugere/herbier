open Brr
module Db = Herbier_store.Db
module Dev_hook = Herbier_bindings.Dev_hook

let cycles = 50
let rounds = 4
let load_timeout_ms = 2000
let poll_ms = 20

(* Long enough for scripts/webview.mjs to read the heap between two rounds. *)
let settle_ms = 1000

(* The run stops at the first precondition that does not hold, with its
   reason; an exception in a later step is such a failure too, rather than a
   page stuck on "running…". *)
module Check = struct
  type 'a t = ('a, string) result Fut.t

  let fail fmt = Printf.ksprintf (fun s -> Fut.return (Error s)) fmt
  let guard f = try f () with e -> fail "exception: %s" (Printexc.to_string e)
  let lift f = Fut.map Result.ok f

  let ( let* ) (f : 'a t) (k : 'a -> 'b t) : 'b t =
    Fut.bind f (function
      | Error e -> Fut.return (Error e)
      | Ok v -> guard (fun () -> k v))
end

let cards el = List.length (El.find_by_class ~root:el (Jstr.v "card-plant"))
let outer_html el = Jv.to_string (Jv.get (El.to_jv el) "outerHTML")
let now () = Performance.now_ms G.performance

let rec until ~ms p =
  let open Fut.Syntax in
  match (p (), ms <= 0) with
  | true, _ -> Fut.return true
  | false, true -> Fut.return false
  | false, false ->
      let* () = Fut.tick ~ms:poll_ms in
      until ~ms:(ms - poll_ms) p

type heap = {gc : bool; used : float option}

let heap () =
  let gc = Dev_hook.collect_garbage () in
  {gc; used = Dev_hook.heap_used ()}

type summary = {
  live_before : int;
  live_rounds : int list;  (** after each round *)
  live_after : int;
  heaps : heap list;  (** before the first round, then after each *)
  control_ms : float;
  stale : int;  (** left screens whose DOM changed *)
}

let run ~db ~stage ~result ~current =
  let open Check in
  let state = Fixture.state () in
  let mount (screen : Screen.t) =
    current := Some screen;
    El.set_children stage [screen.el]
  in
  let unmount (screen : Screen.t) =
    Rb.release screen.bindings;
    current := None;
    El.set_children stage []
  in
  let enter_and_leave i =
    let screen =
      Screens.Collection.v
        (App.create ~db ~state ~theme:(Theme.load ()) ~auth:(Fixture.auth ()))
    in
    mount screen;
    let* filled =
      lift (until ~ms:load_timeout_ms (fun () -> cards screen.el > 0))
    in
    unmount screen;
    match filled with
    | true -> Fut.return (Ok screen.el)
    | false ->
        fail
          "cycle %d: the grid did not fill within %d ms (seed with #dev/seed)" i
          load_timeout_ms
  in
  let rec repeat n left =
    match n with
    | 0 -> Fut.return (Ok left)
    | n ->
        let* el = enter_and_leave (cycles - n + 1) in
        repeat (n - 1) (el :: left)
  in
  let live_before = Rb.live () in
  let heaps = ref [heap ()] and live_rounds = ref [] in
  let rec round k =
    match k > rounds with
    | true -> Fut.return (Ok ())
    | false ->
        let* (_ : El.t list) = repeat cycles [] in
        live_rounds := Rb.live () :: !live_rounds;
        heaps := heap () :: !heaps;
        El.set_at (Jstr.v "data-round") (Some (Jstr.of_int k)) result;
        let* () = lift (Fut.tick ~ms:settle_ms) in
        round (k + 1)
  in
  let* () = round 1 in
  (* The screens left last are kept to see whether a filter change still
     reaches any of them. *)
  let* left = repeat cycles [] in
  let* tags = lift (Db.all db Herbier_store.Tags.list) in
  let* (tag : Herbier_domain.Tag.t) =
    match tags with
    | Ok (t :: _) -> Fut.return (Ok t)
    | Ok [] -> fail "no tag in herbier: seed with #dev/seed first"
    | Error e -> fail "tags: %s" (Db.error_to_string e)
  in
  let control =
    Screens.Collection.v
      (App.create ~db ~state ~theme:(Theme.load ()) ~auth:(Fixture.auth ()))
  in
  mount control;
  let* filled =
    lift (until ~ms:load_timeout_ms (fun () -> cards control.el > 0))
  in
  let shown = cards control.el in
  let snapshots = List.map outer_html left in
  let start = now () in
  State.set_filters state {State.no_filters with tags = [tag.id]};
  let* moved =
    lift (until ~ms:load_timeout_ms (fun () -> cards control.el <> shown))
  in
  let control_ms = now () -. start in
  (* A leaked binding refreshes a left screen through the same store reads as
     the control's: it is given the control's delay again before the look. *)
  let* () = lift (Fut.tick ~ms:(max 300 (int_of_float control_ms))) in
  unmount control;
  State.set_filters state State.no_filters;
  match (filled, moved) with
  | false, _ ->
      fail "control: the grid did not fill within %d ms" load_timeout_ms
  | true, false ->
      fail
        "control: filtering on the tag %S did not change a live grid within %d \
         ms, so the stale check would prove nothing"
        tag.name load_timeout_ms
  | true, true ->
      let stale =
        List.length
          (List.filter
             (fun changed -> changed)
             (List.map2 (fun el s -> outer_html el <> s) left snapshots))
      in
      Fut.return
        (Ok
           {
             live_before;
             live_rounds = List.rev !live_rounds;
             live_after = Rb.live ();
             heaps = List.rev !heaps;
             control_ms;
             stale;
           })

let report result r =
  let set k v = El.set_at (Jstr.v k) (Some (Jstr.v v)) result in
  let text =
    match r with
    | Error reason ->
        set "data-ok" "false";
        "FAILED: " ^ reason
    | Ok s ->
        let ok =
          List.for_all (Int.equal s.live_before) (s.live_after :: s.live_rounds)
          && s.stale = 0
        in
        let ints l = String.concat " " (List.map string_of_int l) in
        let bytes h =
          match h.used with Some b -> Printf.sprintf "%.0f" b | None -> "n/a"
        in
        let mb h =
          match h.used with
          | Some b -> Printf.sprintf "%.1f" (b /. 1e6)
          | None -> "n/a"
        in
        let gc = List.for_all (fun h -> h.gc) s.heaps in
        set "data-live-before" (string_of_int s.live_before);
        set "data-live-rounds" (ints s.live_rounds);
        set "data-live-after" (string_of_int s.live_after);
        set "data-heaps" (String.concat " " (List.map bytes s.heaps));
        set "data-gc" (string_of_bool gc);
        set "data-control-ms" (Printf.sprintf "%.0f" s.control_ms);
        set "data-stale" (string_of_int s.stale);
        set "data-ok" (string_of_bool ok);
        Printf.sprintf
          "%d rounds of %d cycles · bindings %d → %s → %d · heap%s %s MB · \
           control %.0f ms · stale %d of %d · %s"
          rounds cycles s.live_before (ints s.live_rounds) s.live_after
          (match gc with true -> " after GC" | false -> " (no GC)")
          (String.concat " → " (List.map mb s.heaps))
          s.control_ms s.stale cycles
          (match ok with true -> "ok" | false -> "FAILED")
  in
  El.set_children result [El.txt' text]

let el db =
  let result = El.p ~at:[At.id (Jstr.v "result")] [El.txt' "running…"] in
  let stage = El.div [] in
  let root =
    El.div
      [
        El.h1 ~at:[At.class' (Jstr.v "t-screen-title")] [El.txt' "Spike check"];
        result;
        stage;
      ]
  in
  let finish r =
    report result r;
    El.append_children root [El.p [El.txt' "done"]]
  in
  (match db with
  | Error e -> finish (Error ("no herbier database: " ^ e))
  | Ok db ->
      let current = ref None in
      Fut.await
        (Check.guard (fun () -> run ~db ~stage ~result ~current))
        (fun r ->
          Option.iter (fun (s : Screen.t) -> Rb.release s.bindings) !current;
          El.set_children stage [];
          finish r));
  root
