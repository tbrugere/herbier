open Brr
module Tab_bar = Widgets.Tab_bar
module Motion = Herbier_ui_model.Motion
module Navigation = Herbier_bindings.Navigation

(* A route resolved against the build's dev pages: an unknown dev page is
   Collection, like any unknown fragment. *)
type target =
  | Tab_target of Tab_bar.tab
  | Modal_target of Route.modal
  | Dev_target of string * (unit -> Screen.t)

let route_of = function
  | Tab_target t -> Route.Tab t
  | Modal_target m -> Route.Modal m
  | Dev_target (name, _) -> Route.Dev name

(* Two targets are the same screen when their canonical fragments are. *)
let equal_target a b =
  String.equal (Route.to_fragment (route_of a)) (Route.to_fragment (route_of b))

let place_of = function
  | Tab_target Tab_bar.Collection -> Motion.Collection
  | Tab_target (Tab_bar.Map | Journal | Settings) -> Tab
  | Modal_target (Route.Plant id) -> Fiche id
  | Modal_target
      ( Route.Tags | Manage_tags | Edit_plant _ | New_plant | Observation _
      | Change_species _ | Move_point _ | Identify _ | Record | Saved _
      | Viewer _ | Search _ | Link_species _ | Intercepted _ ) ->
      Modal
  | Dev_target _ -> Dev

type shown =
  | Tab_screen of Tab_bar.tab * Screen.t
  | Alone of Screen.t
  | Dev_screen of Screen.t

let screen_of = function Tab_screen (_, s) | Alone s | Dev_screen s -> s

(* Style guide 8.2: the router is the screen boundary. A screen that raises
   is replaced by an error message, so the update step that builds it still
   completes. The bindings it made before raising are never released: they
   stay counted by [Rb.live]. *)
let guarded screen =
  match screen () with
  | s -> s
  | exception ((Out_of_memory | Stack_overflow) as e) -> raise e
  | exception e ->
      Console.(error [str "router: screen failed"; str (Printexc.to_string e)]);
      {
        Screen.el =
          El.div
            ~at:[At.class' (Jstr.v "screen")]
            [El.p [El.txt' "Cet écran n’a pas pu s’ouvrir."]];
        bindings = [];
        ready = Screen.now;
      }

let warn_cap what = function
  | Ok _ -> ()
  | Error e ->
      Console.(warn [str what; str (Herbier_bindings.Cap_error.to_string e)])

(* With [@capacitor/app] installed, Android back does nothing once the WebView
   history is at its start unless a [backButton] listener leaves the app: the
   plugin's own handler only goes back. A tab press replaces its entry, so this
   is where back from any tab exits; a pushed entry (a modal) is walked back. *)
let listen_back_button () =
  let back ~can_go_back =
    match can_go_back with
    | true -> Route.back ()
    | false ->
        Fut.await
          (Herbier_bindings.Cap_app.exit_app ())
          (warn_cap "router: exitApp")
  in
  Fut.await
    (Herbier_bindings.Cap_app.on_back_button back)
    (warn_cap "router: backButton listener")

let start ~root ~tab ~modal ~dev =
  let resolve = function
    | Route.Tab t -> Tab_target t
    | Route.Modal m -> Modal_target m
    | Route.Dev name -> (
        match dev name with
        | Some page -> Dev_target (name, page)
        | None -> Tab_target Tab_bar.Collection)
  in
  (* Rewriting the URL in place keeps it naming what is shown ([""] and
     unknown fragments become [#collection]), so a reload lands on the same
     screen. Called from outside any update step. *)
  let current () =
    let t = resolve (Route.current ()) in
    Route.canonicalize (route_of t);
    t
  in
  let changes, send = React.E.create () in
  let target = React.S.hold ~eq:equal_target (current ()) changes in
  let build = function
    | Tab_target t -> Tab_screen (t, guarded (fun () -> tab t))
    | Modal_target m -> Alone (guarded (fun () -> modal m))
    | Dev_target (_, page) -> Dev_screen (guarded page)
  in
  let shown = React.S.map ~eq:( == ) build target in
  let active =
    React.S.map
      (function
        | Tab_screen (t, _) -> t | Alone _ | Dev_screen _ -> Tab_bar.Collection)
      shown
  in
  let bar = Tab_bar.v ~active in
  let main = El.v (Jstr.v "main") ~at:[At.class' (Jstr.v "shell__screen")] [] in
  let shell = El.div ~at:[At.class' (Jstr.v "shell")] [main; bar.el] in
  let mount = function
    | Tab_screen (_, s) ->
        El.set_children main [s.Screen.el];
        El.set_children root [shell]
    | Alone s | Dev_screen s -> El.set_children root [s.Screen.el]
  in
  (* Dev pages do not hand their bindings to the router, so leaving one
     reloads the page on the new fragment: the leak count of
     [herbierDev.live()] then starts again from the app's baseline. *)
  let leave = function
    | Tab_screen (_, s) | Alone s -> Rb.release s.Screen.bindings
    | Dev_screen _ -> Window.reload G.window
  in
  mount (React.S.value shown);
  let effects =
    [
      Rb.on (React.S.changes shown) mount;
      Rb.on (React.S.diff (fun _ prev -> prev) shown) leave;
      (* A tab switch replaces the history entry: Android back does not
         walk the tabs visited, it leaves the app. *)
      Rb.on bar.select (fun t -> Route.replace (Route.Tab t));
      Rb.on bar.record (fun () -> Route.go (Route.Modal Route.Record));
    ]
  in
  (* react's dependents are weak on js_of_ocaml 6 (see rb.mli): [root] holds
     the effects, which hold [shown] and through it the current screen's
     bindings and the route. The shell's bindings live as long as the app. *)
  Rb.hold root (effects @ bar.bindings);
  (* style: [requested] is the target last handed to a transition, [index]
     the Navigation index at the last hashchange; written by the hashchange
     listener only. A change still waiting in a transition's update is where
     the next one comes from, and a late update sends the newest target, never
     its own (a later Now commit may already have shown it). *)
  let requested = ref (React.S.value target)
  and index = ref (Navigation.current_index ()) in
  let follow _ =
    let next = current () and after = Navigation.current_index () in
    let direction = Motion.direction ~before:!index ~after in
    index := after;
    match equal_target next !requested with
    | true -> ()
    | false ->
        let from = place_of !requested in
        requested := next;
        Transition.run
          (Motion.kind ~from ~to_:(place_of next) direction)
          ~root
          ~commit:(fun () ->
            send !requested;
            screen_of (React.S.value shown))
  in
  ignore (Ev.listen Ev.hashchange follow (Window.as_target G.window));
  listen_back_button ()
