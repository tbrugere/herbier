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
let name db = lenient_find db Drive_root_folder_name ~what:"folder name"

let root_of ~id ~name : Api.root =
  {
    id;
    name =
      Option.value
        (Option.bind name Api.folder_name)
        ~default:Api.default_folder_name;
  }

let read db =
  let open Fut.Result_syntax in
  let* id = stored db in
  let+ name = name db in
  (id, name)

let root db =
  Fut.map (Result.map (fun (id, name) -> root_of ~id ~name)) (read db)

let forget db = Db.write db (Settings.unset Drive_root_folder)

let transaction db stmts =
  Db.bare_transaction db (fun tx ->
      List.fold_left
        (fun acc stmt ->
          let open Fut.Result_syntax in
          let* () = acc in
          let+ (_ : int) = Db.Tx.write_local tx stmt in
          ())
        (Fut.return (Ok ())) stmts)

let apply db ~stored_name (rooted : _ Api.rooted) =
  let root_stmts, root_done =
    match rooted.root with
    | Keep -> ([], None)
    | Store id -> ([Settings.set Drive_root_folder id], Some "stored")
    | Forget -> ([Settings.unset Drive_root_folder], Some "forgotten")
  in
  let name = Api.name_to_store ~stored_name rooted.name in
  let name_stmts =
    Option.to_list
      (Option.map
         (fun (n : Api.folder_name) ->
           Settings.set Drive_root_folder_name (n :> string))
         name)
  in
  match root_stmts @ name_stmts with
  | [] -> Fut.return ()
  | stmts ->
      Fut.map
        (function
          | Ok () ->
              Option.iter log root_done;
              Option.iter
                (fun (_ : Api.folder_name) ->
                  Brr.Console.(log [str "drive: folder name stored"]))
                name
          | Error e -> log_error ("not written: " ^ Db.error_to_string e))
        (transaction db stmts)

let run db program =
  let open Fut.Syntax in
  let* read = read db in
  match read with
  | Error e -> Fut.return (Error e)
  | Ok (id, stored_name) ->
      let* (rooted : _ Api.rooted) =
        program ~root:(root_of ~id ~name:stored_name)
      in
      let+ () = apply db ~stored_name rooted in
      Ok rooted

let account db = lenient_find db Drive_account ~what:"account"

let not_written what e =
  Brr.Console.(
    error [str ("drive: " ^ what ^ " not written: " ^ Db.error_to_string e)])

let store_account db ~account:chosen ~storage =
  let open Fut.Syntax in
  let* stored = account db in
  match stored with
  | Error e ->
      not_written "account" e;
      Fut.return (Error e)
  | Ok stored -> (
      let account = Api.account_to_store ~stored ~account:chosen in
      match
        Settings.drive_choice ~account ~at:(Ptime_clock.now ()) ~storage
      with
      | [] -> Fut.return (Ok ())
      | stmts ->
          let+ written = transaction db stmts in
          (match written with
          | Ok () ->
              Option.iter
                (fun (_ : string) ->
                  Brr.Console.(
                    log [str "drive: account changed, root folder forgotten"]))
                account;
              Option.iter
                (fun (_ : Herbier_domain.Photo.Original_target.t) ->
                  Brr.Console.(log [str "drive: storage set with the account"]))
                storage
          | Error e -> not_written "account" e);
          written)

let seed db ~session_email =
  let open Fut.Result_syntax in
  let* root = stored db in
  let* stored = account db in
  match Api.seed_account ~stored ~root ~session_email with
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
    (transaction db
       [Settings.unset Drive_account; Settings.unset Drive_root_folder])
