module Machine = Herbier_ui_model.Drive_sheet
module Drive_account = Herbier_sync_core.Auth.Drive_account
module Drive_text = Herbier_ui_model.Drive_text

type handlers = {on_change : Machine.t -> unit; on_close : Machine.t -> unit}
type phase = Created | Running of handlers | Released

(* style: mutable fields, the runner's state between JS callbacks; nothing
   outside this module observes them. *)
type t = {
  app : App.t;
  mutable machine : Machine.t;
  mutable opening : Machine.command list;
  mutable phase : phase;
}

let create app ~purpose =
  let machine, opening =
    Machine.open_ ~purpose
      ~stored:
        (Drive_account.email
           (React.S.value (State.account (App.state app))).drive)
      ~folder:(React.S.value (App.drive_folder app))
  in
  {app; machine; opening; phase = Created}

let state t = t.machine

(* A store or a rename that fails after the screen was left shows nowhere: the
   console keeps it. *)
let dropped : Machine.event -> unit = function
  | Stored (Error e) ->
      Log.error ~scope:"drive" "account not stored (screen left)"
        (Drive_text.show_sheet_error e)
  | Renamed (Error e) ->
      Log.error ~scope:"drive" "folder not renamed (screen left)"
        (Drive_text.show_sheet_error e)
  | Stored (Ok ())
  | Renamed (Ok (_ : string))
  | Tap_other_account | Tap_rename _ | Tap_close | Chosen _ | Choose_failed _
  | Token _ ->
      ()

let rec feed t event =
  match t.phase with
  | Created -> ()
  | Released -> dropped event
  | Running handlers ->
      let next, commands = Machine.step t.machine event in
      t.machine <- next;
      handlers.on_change next;
      List.iter (exec t) commands

and exec t : Machine.command -> unit = function
  | Run_chooser ->
      Fut.await (App.choose_account ()) (function
        | Ok email -> feed t (Chosen email)
        | Error e -> feed t (Choose_failed e))
  | Ask_token email ->
      Fut.await (App.folder_token t.app ~email) (fun r -> feed t (Token r))
  | Store_account account ->
      let turn_on =
        match t.machine.purpose with Turn_on -> true | Change -> false
      in
      Fut.await (App.store_account t.app ~account ~turn_on) (fun r ->
          feed t (Stored r))
  | Rename {account; name} ->
      Fut.await (App.rename_folder t.app ~account ~name) (fun r ->
          feed t (Renamed r))
  | Close -> (
      match t.phase with
      | Running handlers ->
          t.phase <- Released;
          handlers.on_close t.machine
      | Created | Released -> ())

let run t ~on_change ~on_close =
  match t.phase with
  | Running _ | Released -> ()
  | Created ->
      t.phase <- Running {on_change; on_close};
      let opening = t.opening in
      t.opening <- [];
      Fut.await (Fut.return ()) (fun () ->
          match t.phase with
          | Running _ -> List.iter (exec t) opening
          | Created | Released -> ())

let release t = t.phase <- Released
