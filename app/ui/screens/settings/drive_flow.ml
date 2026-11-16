module Machine = Herbier_ui_model.Drive_sheet
module Drive_account = Herbier_sync_core.Auth.Drive_account
module Picker = Herbier_bindings.Google_picker

type handlers = {on_change : Machine.t -> unit; on_close : Machine.t -> unit}
type phase = Created | Running of handlers | Released

(* style: mutable fields, the runner's state between JS callbacks; nothing
   outside this module observes them. [ticket]: each token ask takes a new
   one, which the next Picker opening uses. *)
type t = {
  app : App.t;
  mutable machine : Machine.t;
  mutable opening : Machine.command list;
  mutable phase : phase;
  mutable ticket : Picker.ticket;
}

let create app ~purpose =
  let machine, opening =
    Machine.open_ ~purpose
      ~stored:
        (Drive_account.email
           (React.S.value (State.account (App.state app))).drive)
      ~folder:(React.S.value (App.drive_folder app))
      ~picker:App.picker_config
  in
  {app; machine; opening; phase = Created; ticket = Picker.ticket ()}

let state t = t.machine

(* A store that fails after the screen was left shows nowhere: the console
   keeps it. *)
let dropped : Machine.event -> unit = function
  | Stored (Error e) ->
      Log.error ~scope:"drive" "pick not stored (screen left)"
        (Herbier_ui_model.Drive_text.show_pick_error e)
  | Stored (Ok ())
  | Tap_other_account | Tap_browse | Tap_default | Tap_close | Chosen _
  | Choose_failed _ | Token _ | Picker_picked _ | Picker_cancelled
  | Picker_failed _ ->
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
      t.ticket <- Picker.ticket ();
      Fut.await (App.folder_token t.app ~email) (fun r -> feed t (Token r))
  | Open_picker {account; token} ->
      Fut.await (App.open_picker t.app t.ticket ~account ~token) (function
        | Ok (Picked {id; name; _}) -> feed t (Picker_picked {id; name})
        | Ok Cancelled -> feed t Picker_cancelled
        | Error e -> feed t (Picker_failed e))
  | Store_pick {account; folder_id; folder_name} ->
      let turn_on =
        match t.machine.purpose with Turn_on -> true | Change -> false
      in
      Fut.await
        (App.store_pick t.app ~account ~turn_on
           {id = folder_id; name = folder_name})
        (fun r -> feed t (Stored r))
  | Store_default account ->
      Fut.await (App.store_default t.app ~account) (fun r -> feed t (Stored r))
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

(* A closed flow dismisses too: a close from [Browsing] (the sheet's ← under
   the overlay) may leave a Picker on its way. Nothing ran before [run]:
   nothing to dismiss. *)
let release t =
  match t.phase with
  | Created -> t.phase <- Released
  | Running _ | Released ->
      t.phase <- Released;
      Picker.dismiss ()
