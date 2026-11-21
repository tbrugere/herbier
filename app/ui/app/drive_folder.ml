module Db = Herbier_store_io.Db
module Drive_text = Herbier_ui_model.Drive_text
module Api = Herbier_photos.Drive
module Drive = Herbier_photos_io.Drive
module Drive_root = Herbier_photos_io.Drive_root
module Upload_queue = Herbier_photos_io.Upload_queue

let choose_account () = Herbier_sync.Auth.choose_drive_account ()

let folder_token (t : Core.t) ~email =
  Fut.map
    (Result.map_error Core.denial)
    (Core.drive_token_for t ~email ~interactive:true)

(* The storage follows the account: the access check it runs is for that
   account. *)
let stored (t : Core.t) ~account ~storage result =
  let open Fut.Syntax in
  (match result with
  | Ok () ->
      Core.set_drive_account t
        (Herbier_sync_core.Auth.Drive_account.Chosen
           {email = String.trim account})
  | Error (_ : Drive_text.sheet_error) -> ());
  let+ () = Core.refresh_folder t in
  (match result with
  | Ok () ->
      (match storage with
      | Some target -> Core.storage_written t target
      | None -> ());
      Core.upload_pending t;
      Core.check_originals t
  | Error (_ : Drive_text.sheet_error) -> ());
  result

let store_account (t : Core.t) ~account ~turn_on =
  let storage =
    match turn_on with
    | true -> Some Herbier_domain.Photo.Original_target.Drive
    | false -> None
  in
  Fut.bind
    (Upload_queue.exclusive t.uploads
       ~on_raise:(fun (_ : string) -> Error Drive_text.Not_saved)
       (fun () ->
         Fut.map
           (Result.map_error (fun (_ : Db.error) -> Drive_text.Not_saved))
           (Drive_root.store_account t.db ~account ~storage)))
    (stored t ~account ~storage)

let rename (t : Core.t) ~account name =
  Fut.map
    (function
      | Error e ->
          Core.log_error ["drive: rename:"; Db.error_to_string e];
          Error Drive_text.Not_saved
      | Ok ({result = Ok n; _} : _ Api.rooted) ->
          Ok ((n : Api.folder_name) :> string)
      | Ok {result = Error (Drive.Token e); _} ->
          Error (Drive_text.Token (Core.denial e))
      | Ok {result = Error (Drive.Drive (Network (_ : string))); _} ->
          Error Drive_text.Offline
      | Ok {result = Error (Drive.Drive e); _} ->
          Core.log_error ["drive: rename:"; Api.error_to_string e];
          Error Drive_text.Drive_failed)
    (Drive_root.run t.db (fun ~root ->
         Drive.rename_root
           ~token:(fun () ->
             Core.drive_token_for t ~email:account ~interactive:true)
           ~drop_token:(Herbier_sync.Auth.drop_drive_token t.auth)
           ~root ~name))

(* A blank name never reaches Drive. Inside the queue's lock: no pass reads or
   writes the root meanwhile. A name Drive took but the settings did not keep
   is [Not_saved]: the sheet then shows what 4m shows. *)
let rename_folder (t : Core.t) ~account ~name =
  match Api.folder_name name with
  | None -> Fut.return (Error Drive_text.Blank_name)
  | Some name -> (
      let open Fut.Syntax in
      let* result =
        Upload_queue.exclusive t.uploads
          ~on_raise:(fun (_ : string) -> Error Drive_text.Drive_failed)
          (fun () -> rename t ~account name)
      in
      let+ () = Core.refresh_folder t in
      match result with
      | Ok n when not (String.equal n (React.S.value t.drive_folder)) ->
          Core.log_error ["drive: rename: the new name was not stored"];
          Error Drive_text.Not_saved
      | Ok _ | Error _ -> result)

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
