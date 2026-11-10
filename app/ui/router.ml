open Brr
module Tab_bar = Widgets.Tab_bar

type route = Tab of Tab_bar.tab | Dev of string

let dev_prefix = "dev/"

let of_fragment = function
  | "" | "collection" -> Tab Tab_bar.Collection
  | "carte" -> Tab Tab_bar.Map
  | "journal" -> Tab Tab_bar.Journal
  | "reglages" -> Tab Tab_bar.Settings
  | f when String.starts_with ~prefix:dev_prefix f ->
      let n = String.length dev_prefix in
      Dev (String.sub f n (String.length f - n))
  | _ -> Tab Tab_bar.Collection

let to_fragment = function
  | Tab Tab_bar.Collection -> "collection"
  | Tab Tab_bar.Map -> "carte"
  | Tab Tab_bar.Journal -> "journal"
  | Tab Tab_bar.Settings -> "reglages"
  | Dev name -> dev_prefix ^ name

let fragment () = Jstr.to_string (Uri.fragment (Window.location G.window))

let uri_of route =
  Uri.with_uri ~fragment:(Jstr.v (to_fragment route)) (Window.location G.window)

(* A tab switch replaces the history entry instead of adding one: Android
   back does not walk the tabs visited (Material bottom navigation), it
   leaves the app. Fragment navigation still fires [hashchange]
   asynchronously, after this handler returns, so a switch takes the same
   path as back. *)
let switch_to route =
  match uri_of route with
  | Ok uri -> Herbier_bindings.Location.replace uri
  | Error e -> Console.(error [str "router: bad fragment"; str e])

(* A route resolved against the build's dev pages: an unknown dev page is
   Collection, like any unknown fragment. *)
type target =
  | Tab_target of Tab_bar.tab
  | Dev_target of string * (unit -> Screen.t)

let route_of = function
  | Tab_target t -> Tab t
  | Dev_target (name, _) -> Dev name

let equal_target a b =
  match (a, b) with
  | Tab_target a, Tab_target b -> Tab_bar.equal a b
  | Dev_target (a, _), Dev_target (b, _) -> String.equal a b
  | (Tab_target _ | Dev_target _), _ -> false

type shown = Tab_screen of Tab_bar.tab * Screen.t | Dev_screen of Screen.t

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
    | true -> Window.History.back (Window.history G.window)
    | false ->
        Fut.await
          (Herbier_bindings.Cap_app.exit_app ())
          (warn_cap "router: exitApp")
  in
  Fut.await
    (Herbier_bindings.Cap_app.on_back_button back)
    (warn_cap "router: backButton listener")

let start ~root ~tab ~dev =
  let resolve f =
    match of_fragment f with
    | Tab t -> Tab_target t
    | Dev name -> (
        match dev name with
        | Some page -> Dev_target (name, page)
        | None -> Tab_target Tab_bar.Collection)
  in
  (* Rewriting the URL in place keeps it naming what is shown ([""] and
     unknown fragments become [#collection]), so a reload lands on the same
     screen. Called from outside any update step. *)
  let current () =
    let f = fragment () in
    let t = resolve f in
    let canonical = to_fragment (route_of t) in
    (match String.equal f canonical with
    | true -> ()
    | false -> (
        match uri_of (route_of t) with
        | Ok uri -> Window.History.replace_state ~uri (Window.history G.window)
        | Error e -> Console.(error [str "router: bad fragment"; str e])));
    t
  in
  let changes, send = React.E.create () in
  let target = React.S.hold ~eq:equal_target (current ()) changes in
  let build = function
    | Tab_target t -> Tab_screen (t, guarded (fun () -> tab t))
    | Dev_target (_, page) -> Dev_screen (guarded page)
  in
  let shown = React.S.map ~eq:( == ) build target in
  let active =
    React.S.map
      (function Tab_screen (t, _) -> t | Dev_screen _ -> Tab_bar.Collection)
      shown
  in
  let bar = Tab_bar.v ~active in
  let main = El.v (Jstr.v "main") ~at:[At.class' (Jstr.v "shell__screen")] [] in
  let shell = El.div ~at:[At.class' (Jstr.v "shell")] [main; bar.el] in
  let mount = function
    | Tab_screen (_, s) ->
        El.set_children main [s.Screen.el];
        El.set_children root [shell]
    | Dev_screen s -> El.set_children root [s.Screen.el]
  in
  (* Dev pages do not hand their bindings to the router, so leaving one
     reloads the page on the new fragment: the leak count of
     [herbierDev.live()] then starts again from the app's baseline. *)
  let leave = function
    | Tab_screen (_, s) -> Rb.release s.Screen.bindings
    | Dev_screen _ -> Window.reload G.window
  in
  mount (React.S.value shown);
  let effects =
    [
      Rb.on (React.S.changes shown) mount;
      Rb.on (React.S.diff (fun _ prev -> prev) shown) leave;
      Rb.on bar.select (fun t -> switch_to (Tab t));
    ]
  in
  (* react's dependents are weak on js_of_ocaml 6 (see rb.mli): [root] holds
     the effects, which hold [shown] and through it the current screen's
     bindings and the route. The shell's bindings live as long as the app. *)
  Rb.hold root (effects @ bar.bindings);
  ignore
    (Ev.listen Ev.hashchange
       (fun _ -> send (current ()))
       (Window.as_target G.window));
  listen_back_button ()
