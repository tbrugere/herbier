open Brr
module Motion = Herbier_ui_model.Motion
module Plant_id = Herbier_domain.Ids.Plant_id
module View_transition = Herbier_bindings.View_transition
module Media_query = Herbier_bindings.Media_query

type ran =
  | Now
  | Css_fade
  | View of {hero_old : bool; hero_new : bool; outcome : [`Finished | `Skipped]}

type record = {kind : Motion.kind; ran : ran}

let hero_at = Jstr.v "data-hero"
let named_at = Jstr.v "data-hero-named"
let motion_at = Jstr.v "data-motion"
let fade_class = Jstr.v "motion-fade-in"

let mark_hero el id =
  El.set_at hero_at (Some (Jstr.v (Plant_id.to_string id))) el

(* style: module-level, as the document it describes: a view transition is
   per document. [generation] numbers the runs that start one, [named] holds
   the elements the latest of them gave the hero name, [observer] is the dev
   hook. Written only from the hashchange handler, the transition's callbacks
   and [observe] at startup, outside any update step. *)
let generation = ref 0
let named : El.t list ref = ref []
let observer : (record -> unit) option ref = ref None
let observe f = observer := Some f
let report r = Option.iter (fun f -> f r) !observer

let clear_names () =
  List.iter (El.set_at named_at None) !named;
  named := []

(* [view-transition-name] (set by _motion.sass on [data-hero-named]) must be
   unique in each captured state: one name, on one element at a time. *)
let name el =
  El.set_at named_at (Some Jstr.empty) el;
  named := el :: !named

let find_end ~root id =
  let selector =
    Jstr.v (Printf.sprintf "[data-hero=\"%s\"]" (Plant_id.to_string id))
  in
  match El.find_first_by_selector ~root selector with
  | None -> None
  | Some el -> (
      let top = El.bound_y el in
      let bottom = top +. El.bound_h el in
      let viewport_height = Float.of_int (Window.inner_height G.window) in
      match Motion.in_view ~viewport_height ~top ~bottom with
      | true -> Some el
      | false -> None)

let set_motion value =
  El.set_at motion_at (Option.map Jstr.v value) (Document.root G.document)

let fade (screen : Screen.t) = El.set_class fade_class true screen.el

let css_fade kind ~commit =
  fade (commit ());
  report {kind; ran = Css_fade}

let first_of a b =
  let fut, set = Screen.once () in
  Fut.await a set;
  Fut.await b set;
  fut

let view kind ~root ~commit =
  incr generation;
  let mine = !generation in
  let current () = Int.equal mine !generation in
  clear_names ();
  let old_end = Option.bind (Motion.hero kind) (find_end ~root) in
  let kind =
    match old_end with Some _ -> kind | None -> Motion.without_hero kind
  in
  Option.iter name old_end;
  set_motion (Motion.attribute kind);
  (* style: whether the update named the new end, read when the run ends. *)
  let hero_new = ref false in
  let name_new_end id () =
    match current () with
    | false -> ()
    | true -> (
        clear_names ();
        match find_end ~root id with
        | Some el ->
            name el;
            hero_new := true
        | None -> ())
  in
  let update () =
    let (screen : Screen.t) = commit () in
    match Motion.hero kind with
    | None -> Fut.return ()
    | Some id ->
        Fut.map (name_new_end id)
          (first_of screen.ready (Fut.tick ~ms:Motion.ready_cap_ms))
  in
  let clean () =
    match current () with
    | true ->
        clear_names ();
        set_motion None
    | false -> ()
  in
  match View_transition.start update with
  | None ->
      clean ();
      css_fade kind ~commit
  | Some t ->
      Fut.await (View_transition.finished t) (fun outcome ->
          clean ();
          report
            {
              kind;
              ran =
                View
                  {
                    hero_old = Option.is_some old_end;
                    hero_new = !hero_new;
                    outcome;
                  };
            })

let run kind ~root ~commit =
  let supported = View_transition.supported () in
  let reduced = Media_query.matches "(prefers-reduced-motion: reduce)" in
  match Motion.how ~supported ~reduced kind with
  | Motion.Now ->
      ignore (commit () : Screen.t);
      report {kind; ran = Now}
  | Motion.Css_fade -> css_fade kind ~commit
  | Motion.View -> view kind ~root ~commit

let record_to_string {kind; ran} =
  let how, outcome, hero_old, hero_new =
    match ran with
    | Now -> ("now", "immediate", false, false)
    | Css_fade -> ("fade", "immediate", false, false)
    | View {hero_old; hero_new; outcome = `Finished} ->
        ("view", "finished", hero_old, hero_new)
    | View {hero_old; hero_new; outcome = `Skipped} ->
        ("view", "skipped", hero_old, hero_new)
  in
  Printf.sprintf "%s %s %s hero=%d/%d"
    (Option.value ~default:"instant" (Motion.attribute kind))
    how outcome (Bool.to_int hero_old) (Bool.to_int hero_new)
