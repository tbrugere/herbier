module Db = Herbier_store_io.Db
module Settings = Herbier_store.Settings
module Api = Herbier_photos.Drive

let log line = Brr.Console.(log [str ("drive: root folder " ^ line)])
let log_error line = Brr.Console.(error [str ("drive: root folder " ^ line)])

(* A value that does not decode reads as unset, with a console error. *)
let lenient_find db key ~what =
  Fut.map
    (function
      | Ok v -> Ok v
      | Error (Db.Decode {error = Row `WrongType; _} as e) ->
          Brr.Console.(
            error
              [str ("drive: " ^ what ^ " unreadable: " ^ Db.error_to_string e)]);
          Ok None
      | Error e -> Error e)
    (Db.find db (Settings.get key))

let stored db = lenient_find db Drive_root_folder ~what:"root folder"
let forget db = Db.write db (Settings.unset Drive_root_folder)

let written done_ =
  Fut.map (function
    | Ok (_ : int) -> log done_
    | Error e -> log_error ("not written: " ^ Db.error_to_string e))

let apply db : Api.root_change -> unit Fut.t = function
  | Keep -> Fut.return ()
  | Store id ->
      written "stored" (Db.write db (Settings.set Drive_root_folder id))
  | Forget -> written "forgotten" (forget db)

let run db program =
  let open Fut.Syntax in
  let* stored = stored db in
  match stored with
  | Error e -> Fut.return (Error e)
  | Ok root ->
      let* (rooted : _ Api.rooted) = program ~root in
      let+ () = apply db rooted.root in
      Ok rooted

let picked db = lenient_find db Drive_root_folder_picked ~what:"picked folder"

let read_choice db =
  let open Fut.Result_syntax in
  let* root = stored db in
  let+ folder = picked db in
  (root, folder)

let read_ids db =
  let open Fut.Result_syntax in
  let* root, folder = read_choice db in
  let+ default =
    lenient_find db Drive_root_folder_default ~what:"default folder"
  in
  let picked = Option.map (fun (f : Settings.drive_folder) -> f.id) folder in
  ({Api.root; picked; default} : Api.root_ids)

let account db = lenient_find db Drive_account ~what:"account"

(* The account, the three keys and, when given, the storage target in one
   transaction: a half-written choice could name one folder in 4m while
   uploads go into another, keep an old account's folder ids for the new
   account, or leave the storage on Drive without its folder. *)
let write db ({account; ids} : Api.account_choice) ~picked ~storage ~done_ =
  let open Fut.Result_syntax in
  Fut.map
    (function
      | Ok () ->
          (match account with
          | Some (_ : string) ->
              Brr.Console.(
                log [str "drive: account changed, root folder forgotten"])
          | None -> ());
          (match storage with
          | Some (_ : Herbier_domain.Photo.Original_target.t) ->
              Brr.Console.(log [str "drive: storage set with the pick"])
          | None -> ());
          Ok (log done_)
      | Error e ->
          log_error ("not written: " ^ Db.error_to_string e);
          Error e)
    (Db.bare_transaction db (fun tx ->
         List.fold_left
           (fun acc stmt ->
             let* () = acc in
             let+ (_ : int) = Db.Tx.write_local tx stmt in
             ())
           (Fut.return (Ok ()))
           (Settings.drive_choice ~account ~at:(Ptime_clock.now ())
              ~root:ids.root ~picked ~default:ids.default ~storage)))

let read_all db =
  let open Fut.Result_syntax in
  let* ids = read_ids db in
  let+ stored = account db in
  (ids, stored)

let choose db ~account ~storage (folder : Settings.drive_folder) =
  let open Fut.Result_syntax in
  let* ids, stored = read_all db in
  write db
    (Api.choose_for_account ids ~stored ~account ~folder:(Some folder.id))
    ~picked:(Some folder) ~storage ~done_:"picked"

let reset db ~account =
  let open Fut.Result_syntax in
  let* ids, stored = read_all db in
  write db
    (Api.choose_for_account ids ~stored ~account ~folder:None)
    ~picked:None ~storage:None ~done_:"reset"

let seed db ~session_email =
  let open Fut.Result_syntax in
  let* ids, stored = read_all db in
  match Api.seed_account ~stored ids ~session_email with
  | None -> Fut.return (Ok None)
  | Some email ->
      let+ (_ : int) = Db.write db (Settings.set Drive_account email) in
      log "kept for the signed-in account";
      Some email

let forget_account db =
  Fut.map
    (function
      | Ok () ->
          log "forgotten with the account";
          Ok ()
      | Error e ->
          log_error ("not written: " ^ Db.error_to_string e);
          Error e)
    (Db.bare_transaction db (fun tx ->
         List.fold_left
           (fun acc stmt ->
             let open Fut.Result_syntax in
             let* () = acc in
             let+ (_ : int) = Db.Tx.write_local tx stmt in
             ())
           (Fut.return (Ok ()))
           (Settings.unset Drive_account
           :: Settings.drive_choice ~account:None ~at:(Ptime_clock.now ())
                ~root:None ~picked:None ~default:None ~storage:None)))
