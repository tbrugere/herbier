open Brr
module Db = Herbier_store_io.Db
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
   not parse (Settings.get), is [None]. *)
let stored db key =
  Fut.map
    (function
      | Ok v -> Ok v | Error (Db.Decode _) -> Ok None | Error e -> Error e)
    (Db.find db (Settings.get key))

let setting db key default =
  Fut.map (Result.map (Option.value ~default)) (stored db key)

type settings = {
  storage : Original_target.t;
  drive : Herbier_sync_core.Auth.Drive_account.t;
  wifi_only : bool;
  place_sources : Herbier_geo.Place_name.sources;
  identification : Herbier_ui_model.Identify_settings.settings;
}

let place_sources db =
  let module Place_name = Herbier_geo.Place_name in
  let open Fut.Result_syntax in
  List.fold_left
    (fun acc source ->
      let* sources = acc in
      let+ on = setting db (Herbier_ui.App.settings_key source) false in
      Place_name.set sources source on)
    (Fut.return (Ok Place_name.none))
    Place_name.order

let settings db =
  let open Fut.Result_syntax in
  let* storage = setting db Settings.Storage_target Original_target.App_only in
  let* wifi_only = setting db Settings.Wifi_only false in
  let* drive_account = Herbier_photos_io.Drive_root.account db in
  let* place_sources = place_sources db in
  let* on_photo = stored db Settings.Identify_on_photo in
  let+ flora = stored db Settings.Plantnet_project in
  let drive =
    Herbier_sync_core.Auth.Drive_account.of_stored
      ~configured:Herbier_sync.Auth.drive_configured drive_account
  in
  {
    storage;
    drive;
    wifi_only;
    place_sources;
    identification =
      Herbier_ui_model.Identify_settings.settings_of_stored ~on_photo ~flora;
  }

let tab app = function
  | Herbier_ui.Widgets.Tab_bar.Collection -> Herbier_ui.Screens.Collection.v app
  | Journal -> Herbier_ui.Screens.Journal.v app
  | Settings -> Herbier_ui.Screens.Settings.v app
  | Map -> Herbier_ui.Screens.Map_tab.v app

let modal app = function
  | Herbier_ui.Route.Tags -> Herbier_ui.Screens.Tags.v app
  | Herbier_ui.Route.Drive_folder -> Herbier_ui.Screens.Settings.drive_sheet app
  | Herbier_ui.Route.Plant id -> Herbier_ui.Screens.Species.v app id
  | Herbier_ui.Route.Edit_plant id ->
      Herbier_ui.Screens.Edit_plant.v app
        (Herbier_ui.Screens.Edit_plant.Edit id)
  | Herbier_ui.Route.Observation id -> Herbier_ui.Screens.Observation.v app id
  | Herbier_ui.Route.Change_species id ->
      Herbier_ui.Screens.Resolve.v app (Herbier_ui.Screens.Resolve.Change id)
  | Herbier_ui.Route.Move_point id -> Herbier_ui.Screens.Move_point.v app id
  | Herbier_ui.Route.Identify id ->
      Herbier_ui.Screens.Resolve.v app (Herbier_ui.Screens.Resolve.Identify id)
  | Herbier_ui.Route.Search q ->
      Herbier_ui.Screens.Resolve.v app (Herbier_ui.Screens.Resolve.Search q)
  | Herbier_ui.Route.Link_species id ->
      Herbier_ui.Screens.Resolve.v app
        (Herbier_ui.Screens.Resolve.Link_plant id)
  | Herbier_ui.Route.Intercepted {text; outside} ->
      Herbier_ui.Screens.Resolve.v app
        (Herbier_ui.Screens.Resolve.Intercept {text; outside})
  | Herbier_ui.Route.Record -> Herbier_ui.Screens.Record.v app
  | Herbier_ui.Route.Recorded {observation; identify} ->
      Herbier_ui.Screens.Observation.v
        ~arrival:(Recorded {identify})
        app observation
  | Herbier_ui.Route.Viewer id -> Herbier_ui.Screens.Viewer.v app id
  | Herbier_ui.Route.Reference_photo {plant; organ} ->
      Herbier_ui.Screens.Viewer.reference app plant organ
  | Herbier_ui.Route.New_plant ->
      Herbier_ui.Screens.Edit_plant.v app Herbier_ui.Screens.Edit_plant.New

(* The theme is read once, here: app.css is loaded by now. [online] starts
   from the navigator and {!watch_network} keeps it current. *)
let create_app db {storage; drive; wifi_only; place_sources; identification} =
  let auth = Herbier_sync.Auth.create () in
  let state =
    Herbier_ui.State.create
      ~network:{online = Navigator.online G.navigator}
      ~account:{auth = Herbier_sync.Auth.status auth; storage; drive; wifi_only}
      ~place_sources
  in
  Herbier_ui.App.create ~db ~state ~theme:(Herbier_ui.Theme.load ()) ~auth
    ~identification

(* The window's online and offline events update [State.network]; coming
   back online asks the enabled place-name sources for what was saved
   meanwhile (architecture §8), runs the originals' queue and the Drive health
   check when it is due (architecture §5), and fetches the references of the
   plants whose fetch never completed (architecture §6). The window holds
   the listeners for the app's lifetime. *)
let watch_network app =
  let state = Herbier_ui.App.state app in
  let set online (_ : Ev.Type.void Ev.t) =
    Herbier_ui.State.set_network state {online};
    match online with
    | true ->
        Herbier_ui.App.geocode_pending app;
        Herbier_ui.App.upload_pending app;
        Herbier_ui.App.check_originals app;
        Herbier_ui.App.fetch_pending_references ~back_online:true app
    | false -> ()
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
    ready = Herbier_ui.Screen.now;
  }

let or_unavailable screen app =
  match app with Ok app -> screen app | Error msg -> unavailable msg

let () =
  let root = root () in
  El.set_children root
    [El.p ~at:[At.class' (Jstr.v "screen")] [El.txt' "Chargement…"]];
  Herbier_ui.Widgets.Toast.mount ();
  Fut.await (start ()) (fun (db, app) ->
      (match app with
      | Ok app -> (
          watch_network app;
          Herbier_ui.App.start_auth app;
          Herbier_ui.App.start_sync app;
          Herbier_ui.App.start_keepalive app;
          Herbier_ui.App.start_uploads app;
          Herbier_ui.App.start_france app;
          Herbier_ui.App.geocode_pending app;
          (* The network may have come back between two sessions; offline,
             the pass returns at once. *)
          Herbier_ui.App.fetch_pending_references app;
          Fut.await (Herbier_ui.App.load_plantnet_key app) Fun.id;
          (* A veil over a dev page would cover the emulator's checks; the
             notice shows at the next start on an app route. *)
          match Herbier_ui.Route.current () with
          | Dev _ -> ()
          | Tab _ | Modal _ -> Herbier_ui.Location_notice.show_once app)
      | Error reason -> Console.(error [str "herbier: startup"; str reason]));
      let route =
        Herbier_ui.Router.start ~root ~tab:(or_unavailable tab app)
          ~modal:(or_unavailable modal app) ~dev:(Dev_pages.find db app)
      in
      (* After the router: a link that started the app opens 4j above the
         collection, and the plugins keep it until this listener exists. *)
      match app with
      | Ok app ->
          let offline_banner = Herbier_ui.Offline_banner.mount app ~route in
          Herbier_ui.System_bars.start ~route ~offline_banner;
          Herbier_ui.Intake.start app
      | Error _ ->
          Herbier_ui.System_bars.start ~route
            ~offline_banner:(React.S.const false))
