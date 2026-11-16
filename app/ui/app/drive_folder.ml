module Db = Herbier_store_io.Db
module Drive_text = Herbier_ui_model.Drive_text
module Drive_sheet = Herbier_ui_model.Drive_sheet
module Picker = Herbier_bindings.Google_picker
module Drive = Herbier_photos_io.Drive
module Drive_root = Herbier_photos_io.Drive_root
module Upload_queue = Herbier_photos_io.Upload_queue

let project_number = Herbier_sync.Backend.google_cloud_project_number
let picker_config = Drive_text.picker_config_of_project_number project_number
let choose_account () = Herbier_sync.Auth.choose_drive_account ()

let folder_token (t : Core.t) ~email =
  Fut.map
    (Result.map_error Core.denial)
    (Core.drive_token_for t ~email ~interactive:true)

let open_picker (t : Core.t) ticket ~account ~token =
  let config =
    {
      Picker.app_id = project_number;
      developer_key = None;
      origin = Herbier_bindings.Location.origin ();
    }
  in
  Fut.map
    (function
      | Ok outcome -> Ok outcome
      | Error e -> (
          Core.log_error ["drive: picker:"; Picker.error_to_string e];
          match (e, Core.online t) with
          | Load_failed (_ : string), false -> Error Drive_text.Offline
          | Load_failed (_ : string), true | (Picker_failed _ | Busy), _ ->
              Error Drive_text.Picker_unavailable))
    (Picker.pick_folder
       ~title:(Drive_sheet.picker_title account)
       ticket config ~token)

(* Checked with files.get before it is stored, with the sheet's account (not
   stored yet when it changes): the pick must be a folder this token can reach
   (Picker's setAppId adds it to the app's drive.file grant), and the name
   shown is Drive's. *)
let check_and_store (t : Core.t) ~account
    (p : Herbier_store.Settings.drive_folder) =
  let open Fut.Syntax in
  let* info =
    Drive.folder_info
      ~token:(fun () ->
        Core.drive_token_for t ~email:account ~interactive:false)
      ~drop_token:(Herbier_sync.Auth.drop_drive_token t.auth)
      ~file_id:p.id
  in
  match info with
  | Ok (Usable {id; name}) ->
      Fut.map
        (Result.map_error (fun (_ : Db.error) -> Drive_text.Not_saved))
        (Drive_root.choose t.db ~account {id; name})
  | Ok Not_a_folder -> Fut.return (Error Drive_text.Not_a_folder)
  | Ok Folder_trashed -> Fut.return (Error Drive_text.Trashed)
  | Ok No_access -> Fut.return (Error Drive_text.No_access)
  | Error (Token e) -> Fut.return (Error (Drive_text.Token (Core.denial e)))
  | Error (Drive (Network (_ : string))) ->
      Fut.return (Error Drive_text.Offline)
  | Error (Drive e) ->
      Core.log_error
        ["drive: picked folder:"; Herbier_photos.Drive.error_to_string e];
      Fut.return (Error Drive_text.Drive_failed)

(* After a write: the account into State (and the last token outcome forgotten
   when it changed), then the folder read, then a pass and the health check:
   rows not started yet go to the new root. *)
let stored (t : Core.t) ~account result =
  let open Fut.Syntax in
  (match result with
  | Ok () ->
      Core.set_drive_account t
        (Herbier_sync_core.Auth.Drive_account.Chosen
           {email = String.trim account})
  | Error (_ : Drive_text.pick_error) -> ());
  let+ () = Core.refresh_folder t in
  (match result with
  | Ok () ->
      Core.upload_pending t;
      Core.check_originals t
  | Error (_ : Drive_text.pick_error) -> ());
  result

let store_pick (t : Core.t) ~account folder =
  Fut.bind
    (Upload_queue.exclusive t.uploads
       ~on_raise:(fun (_ : string) -> Error Drive_text.Drive_failed)
       (fun () -> check_and_store t ~account folder))
    (stored t ~account)

let store_default (t : Core.t) ~account =
  Fut.bind
    (Upload_queue.exclusive t.uploads
       ~on_raise:(fun (_ : string) -> Error Drive_text.Not_saved)
       (fun () ->
         Fut.map
           (Result.map_error (fun (_ : Db.error) -> Drive_text.Not_saved))
           (Drive_root.reset t.db ~account)))
    (stored t ~account)

let forget_account (t : Core.t) =
  let open Fut.Syntax in
  let* forgotten =
    Upload_queue.exclusive t.uploads
      ~on_raise:(fun e -> Error (Db.Raised e))
      (fun () -> Drive_root.forget_account t.db)
  in
  (match forgotten with
  | Ok () -> Core.set_drive_account t Unchosen
  | Error (_ : Db.error) -> ());
  let+ () = Core.refresh_folder t in
  forgotten
