open Brr
module Db = Herbier_store.Db
module Settings = Herbier_store.Settings
module Original_target = Herbier_domain.Photo.Original_target

let root () =
  match Document.find_el_by_id G.document (Jstr.v "app") with
  | Some root -> root
  | None ->
      let root = El.div [] in
      El.append_children (Document.body G.document) [root];
      root

(* A setting as the app starts with it: unset, or a stored value that does
   not parse (Settings.get), is the default given here. *)
let setting db key default =
  Fut.map
    (function
      | Ok (Some v) -> Ok v
      | Ok None | Error (Db.Decode _) -> Ok default
      | Error e -> Error e)
    (Db.find db (Settings.get key))

let settings db =
  let open Fut.Syntax in
  let* storage = setting db Settings.Storage_target Original_target.App_only in
  let+ wifi_only = setting db Settings.Wifi_only false in
  Result.bind storage (fun storage ->
      Result.map (fun wifi_only -> (storage, wifi_only)) wifi_only)

let tab app = function
  | Herbier_ui.Widgets.Tab_bar.Collection -> Herbier_ui.Screens.Collection.v app
  | Journal -> Herbier_ui.Screens.Journal.v app
  | Settings -> Herbier_ui.Screens.Settings.v app
  | Map -> Herbier_ui.Screens.Map_tab.v app

let modal app = function
  | Herbier_ui.Route.Tags -> Herbier_ui.Screens.Tags.v app
  | Herbier_ui.Route.Manage_tags -> Herbier_ui.Screens.Manage_tags.v app
  | Herbier_ui.Route.Plant id -> Herbier_ui.Screens.Species.v app id
  | Herbier_ui.Route.Edit_plant id ->
      Herbier_ui.Screens.Edit_plant.v app
        (Herbier_ui.Screens.Edit_plant.Edit id)
  | Herbier_ui.Route.Observation id -> Herbier_ui.Screens.Observation.v app id
  | Herbier_ui.Route.Change_species id ->
      Herbier_ui.Screens.Resolve.v app (Herbier_ui.Screens.Resolve.Change id)
  | Herbier_ui.Route.Identify id ->
      Herbier_ui.Screens.Resolve.v app (Herbier_ui.Screens.Resolve.Identify id)
  | Herbier_ui.Route.Search q ->
      Herbier_ui.Screens.Resolve.v app (Herbier_ui.Screens.Resolve.Search q)
  | Herbier_ui.Route.Link_species id ->
      Herbier_ui.Screens.Resolve.v app
        (Herbier_ui.Screens.Resolve.Link_plant id)
  | Herbier_ui.Route.Record -> Herbier_ui.Screens.Record.v app
  | Herbier_ui.Route.Saved id -> Herbier_ui.Screens.Saved.v app id
  | Herbier_ui.Route.Viewer id -> Herbier_ui.Screens.Viewer.v app id
  | Herbier_ui.Route.New_plant ->
      Herbier_ui.Screens.Edit_plant.v app Herbier_ui.Screens.Edit_plant.New

(* The theme is read once, here: app.css is loaded by now. [online] starts
   from the navigator and {!watch_network} keeps it current. *)
let create_app db (storage, wifi_only) =
  let state =
    Herbier_ui.State.create
      ~network:{online = Navigator.online G.navigator; pending_uploads = 0}
      ~account:{google_signed_in = false; storage; wifi_only}
  in
  Herbier_ui.App.create ~db ~state ~theme:(Herbier_ui.Theme.load ())

(* The window's online and offline events update [State.network]; coming
   back online geocodes what was saved meanwhile (architecture §8). The
   window holds the listeners for the app's lifetime. *)
let watch_network app =
  let state = Herbier_ui.App.state app in
  let set online (_ : Ev.Type.void Ev.t) =
    let network = React.S.value (Herbier_ui.State.network state) in
    Herbier_ui.State.set_network state {network with online};
    match online with true -> Herbier_ui.App.geocode_pending app | false -> ()
  in
  let listen name online =
    ignore
      (Ev.listen
         (Ev.Type.void (Jstr.v name))
         (set online)
         (Window.as_target G.window)
        : Ev.listener)
  in
  listen "online" true;
  listen "offline" false

(* What the router gets: the database for the dev pages and the app for the
   tabs, or why there is none. An exception while building the app (a bug)
   is a failure too, so the screen says so instead of staying blank. *)
let start () =
  let open Fut.Syntax in
  let* opened = Db.open_ ~database:"herbier" in
  match opened with
  | Error e ->
      let msg = Db.error_to_string e in
      Fut.return (Error msg, Error msg)
  | Ok db ->
      let+ settings = settings db in
      let app =
        match settings with
        | Error e -> Error (Db.error_to_string e)
        | Ok settings -> (
            match create_app db settings with
            | app -> Ok app
            | exception ((Out_of_memory | Stack_overflow) as e) -> raise e
            | exception e -> Error (Printexc.to_string e))
      in
      (Ok db, app)

(* Every screen of the app when it could not start; the dev pages stay
   reachable. *)
let unavailable msg _ =
  {
    Herbier_ui.Screen.el =
      El.div
        ~at:[At.class' (Jstr.v "screen")]
        [El.p [El.txt' "Herbier n’a pas pu démarrer."]; El.p [El.txt' msg]];
    bindings = [];
  }

let or_unavailable screen app =
  match app with Ok app -> screen app | Error msg -> unavailable msg

let () =
  let root = root () in
  El.set_children root
    [El.p ~at:[At.class' (Jstr.v "screen")] [El.txt' "Chargement…"]];
  Fut.await (start ()) (fun (db, app) ->
      (match app with
      | Ok app ->
          watch_network app;
          Herbier_ui.App.geocode_pending app
      | Error reason -> Console.(error [str "herbier: startup"; str reason]));
      Herbier_ui.Router.start ~root ~tab:(or_unavailable tab app)
        ~modal:(or_unavailable modal app) ~dev:(Dev_pages.find db app))
