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

let set_or_unset tx key = function
  | Some v -> Db.Tx.write_local tx (Settings.set key v)
  | None -> Db.Tx.write_local tx (Settings.unset key)

(* The three keys in one transaction: a half-written choice could name one
   folder in 4m while uploads go into another. *)
let write db (ids : Api.root_ids) ~picked ~done_ =
  let open Fut.Result_syntax in
  Fut.map
    (function
      | Ok () -> Ok (log done_)
      | Error e ->
          log_error ("not written: " ^ Db.error_to_string e);
          Error e)
    (Db.bare_transaction db (fun tx ->
         let* (_ : int) = set_or_unset tx Drive_root_folder ids.root in
         let* (_ : int) = set_or_unset tx Drive_root_folder_picked picked in
         let+ (_ : int) =
           set_or_unset tx Drive_root_folder_default ids.default
         in
         ()))

let choose db (folder : Settings.drive_folder) =
  let open Fut.Result_syntax in
  let* ids = read_ids db in
  write db
    (Api.pick_root ids ~id:folder.id)
    ~picked:(Some folder) ~done_:"picked"

let reset db =
  let open Fut.Result_syntax in
  let* ids = read_ids db in
  write db (Api.default_root ids) ~picked:None ~done_:"reset"
