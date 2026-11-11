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

(* A stored value that does not parse is unset too (Settings.get). *)
let storage db =
  Fut.map
    (function
      | Ok (Some t) -> Ok t
      | Ok None | Error (Db.Decode _) -> Ok Original_target.App_only
      | Error e -> Error e)
    (Db.find db (Settings.get Settings.Storage_target))

let tab app = function
  | Herbier_ui.Widgets.Tab_bar.Collection -> Herbier_ui.Screens.Collection.v app
  | Journal -> Herbier_ui.Screens.Journal.v app
  | (Map | Settings) as t -> Herbier_ui.Screens.Placeholder.v t

let modal app = function
  | Herbier_ui.Route.Tags -> Herbier_ui.Screens.Tags.v app
  | Herbier_ui.Route.Manage_tags -> Herbier_ui.Screens.Manage_tags.v app
  | Herbier_ui.Route.Plant id -> Herbier_ui.Screens.Species.v app id
  | Herbier_ui.Route.Edit_plant id ->
      Herbier_ui.Screens.Edit_plant.v app
        (Herbier_ui.Screens.Edit_plant.Edit id)
  | Herbier_ui.Route.New_plant ->
      Herbier_ui.Screens.Edit_plant.v app Herbier_ui.Screens.Edit_plant.New

(* [online] is read once, here: no online or offline listener updates it. *)
let create_app db storage =
  let state =
    Herbier_ui.State.create
      ~network:{online = Navigator.online G.navigator; pending_uploads = 0}
      ~account:{google_signed_in = false; storage}
  in
  Herbier_ui.App.create ~db ~state

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
      let+ storage = storage db in
      let app =
        match storage with
        | Error e -> Error (Db.error_to_string e)
        | Ok storage -> (
            match create_app db storage with
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
      | Ok (_ : Herbier_ui.App.t) -> ()
      | Error reason -> Console.(error [str "herbier: startup"; str reason]));
      Herbier_ui.Router.start ~root ~tab:(or_unavailable tab app)
        ~modal:(or_unavailable modal app) ~dev:(Dev_pages.find db))
