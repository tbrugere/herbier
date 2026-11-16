module Db = Herbier_store_io.Db
module Drive_text = Herbier_ui_model.Drive_text
module Picker = Herbier_bindings.Google_picker
module Drive = Herbier_photos_io.Drive
module Drive_root = Herbier_photos_io.Drive_root
module Upload_queue = Herbier_photos_io.Upload_queue

let project_number = Herbier_sync.Backend.google_cloud_project_number
let picker_config = Drive_text.picker_config_of_project_number project_number

(* Checked with files.get before it is stored: the pick must be a folder this
   token can reach (Picker's setAppId adds it to the app's drive.file grant),
   and the name shown is Drive's. *)
let check_and_store (t : Core.t) (p : Picker.picked) =
  let open Fut.Syntax in
  let* info =
    Drive.folder_info
      ~token:(fun () -> Core.drive_token t ~interactive:false)
      ~drop_token:(Herbier_sync.Auth.drop_drive_token t.auth)
      ~file_id:p.id
  in
  match info with
  | Ok (Usable {id; name}) ->
      Fut.map
        (Result.map_error (fun (_ : Db.error) -> Drive_text.Not_saved))
        (Drive_root.choose t.db {id; name})
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

let choose_drive_folder (t : Core.t) =
  let open Fut.Syntax in
  let ticket = Picker.ticket () in
  let* token = Core.drive_token t ~interactive:true in
  match token with
  | Error e -> Fut.return (Error (Drive_text.Token (Core.denial e)))
  | Ok token -> (
      let config =
        {
          Picker.app_id = project_number;
          developer_key = None;
          origin = Herbier_bindings.Location.origin ();
        }
      in
      let* picked = Picker.pick_folder ticket config ~token in
      match picked with
      | Error e -> (
          Core.log_error ["drive: picker:"; Picker.error_to_string e];
          match (e, Core.online t) with
          | Load_failed (_ : string), false ->
              Fut.return (Error Drive_text.Offline)
          | Load_failed (_ : string), true | (Picker_failed _ | Busy), _ ->
              Fut.return (Error Drive_text.Picker_unavailable))
      | Ok Cancelled -> Fut.return (Ok ())
      | Ok (Picked p) ->
          let* stored =
            Upload_queue.exclusive t.uploads
              ~on_raise:(fun (_ : string) -> Error Drive_text.Drive_failed)
              (fun () -> check_and_store t p)
          in
          let+ () = Core.refresh_folder t in
          (match stored with
          | Ok () -> Core.upload_pending t
          | Error (_ : Drive_text.pick_error) -> ());
          stored)

let default_drive_folder (t : Core.t) =
  let open Fut.Syntax in
  let* reset =
    Upload_queue.exclusive t.uploads
      ~on_raise:(fun m -> Error (Db.Raised m))
      (fun () -> Drive_root.reset t.db)
  in
  let+ () = Core.refresh_folder t in
  reset
