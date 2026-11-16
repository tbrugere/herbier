module Db = Herbier_store_io.Db
module Settings = Herbier_store.Settings
module Api = Herbier_photos.Drive

let log line = Brr.Console.(log [str ("drive: root folder " ^ line)])
let log_error line = Brr.Console.(error [str ("drive: root folder " ^ line)])

let stored db =
  Fut.map
    (function
      | Ok v -> Ok v
      | Error (Db.Decode {error = Row `WrongType; _} as e) ->
          log_error ("unreadable: " ^ Db.error_to_string e);
          Ok None
      | Error e -> Error e)
    (Db.find db (Settings.get Drive_root_folder))

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
