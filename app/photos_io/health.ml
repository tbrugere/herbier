module Db = Herbier_store_io.Db
module Settings = Herbier_store.Settings
module Photos = Herbier_store.Photos
module Check = Herbier_photos.Health

type t = {
  db : Db.t;
  commit : Herbier_store.Outbox.edit list -> (int, Db.error) result Fut.t;
  token : unit -> (string, string) result Fut.t;
  drop_token : string -> unit Fut.t;
  running : bool ref;
      (* style: mutable because a check settles in a future's callback; the
         single-flight flag, nothing outside this module sees it. *)
}

let create ~db ~commit ~token ~drop_token =
  {db; commit; token; drop_token; running = ref false}

type outcome =
  | Not_due
  | Busy
  | Checked of Check.report
  | Stopped of string Drive.error
  | Raised of string
  | Store of Db.error

let outcome_to_string = function
  | Not_due -> "not due"
  | Busy -> "busy"
  | Checked report -> Check.summary report
  | Stopped e -> "stopped: " ^ Drive.error_to_string Fun.id e
  | Raised e -> "raised: " ^ e
  | Store e -> "store: " ^ Db.error_to_string e

let log line = Brr.Console.(log [str ("health: " ^ line)])

let last_checked t =
  Fut.map
    (function
      | Ok last -> last
      | Error e ->
          log ("last check unreadable: " ^ Db.error_to_string e);
          None)
    (Db.find t.db (Settings.get Drive_health_checked_at))

let cursor t =
  Fut.map
    (function
      | Ok cursor -> cursor
      | Error e ->
          log ("cursor unreadable: " ^ Db.error_to_string e);
          None)
    (Db.find t.db (Settings.get Drive_health_cursor))

let write t what stmt =
  Fut.map
    (function
      | Ok (_ : int) -> ()
      | Error e -> log (what ^ " not written: " ^ Db.error_to_string e))
    (Db.write t.db stmt)

(* A stopped round resumes after the last photo it reached. *)
let keep_cursor t = function
  | None -> Fut.return ()
  | Some id -> write t "cursor" (Settings.set Drive_health_cursor id)

let end_round t ~now =
  let open Fut.Syntax in
  let* () = write t "date" (Settings.set Drive_health_checked_at now) in
  write t "cursor" (Settings.unset Drive_health_cursor)

let commit_changes t ~now (changes : Check.change list) =
  match changes with
  | [] -> Fut.return (Ok 0)
  | changes ->
      t.commit
        (List.map
           (fun ({item; state} : Check.change) ->
             Photos.set_upload item.photo_id ~state
               ~drive_file_id:(Some item.file_id) ~at:now)
           changes)

let check t ~now =
  let open Fut.Syntax in
  let* photos = Db.all t.db Photos.in_drive in
  match photos with
  | Error e -> Fut.return (Store e)
  | Ok photos -> (
      let* after = cursor t in
      let* asked =
        Drive.health ~token:t.token ~drop_token:t.drop_token
          (Check.resume ~after (Check.items photos))
      in
      match asked with
      | Error e -> Fut.return (Stopped e)
      | Ok report -> (
          let* committed = commit_changes t ~now report.changes in
          match (committed, report.stopped) with
          | Error e, (Some _ | None) -> Fut.return (Store e)
          | Ok (_ : int), Some e ->
              let+ () = keep_cursor t report.reached in
              Stopped (Drive.Drive e)
          | Ok (_ : int), None ->
              let+ () = end_round t ~now in
              Checked report))

(* As Upload_queue's pass: a raise before the check's first future would
   leave the single-flight flag set for good, so it ends the check. *)
let safe_check t ~now =
  match check t ~now with
  | fut -> fut
  | exception ((Failure _ | Invalid_argument _ | Not_found | Jv.Error _) as e)
    ->
      Fut.return (Raised (Printexc.to_string e))

let due t ~force ~now =
  match force with
  | true -> Fut.return true
  | false -> Fut.map (fun last -> Check.due ~now ~last) (last_checked t)

let run t ~force =
  let open Fut.Syntax in
  match !(t.running) with
  | true ->
      log (outcome_to_string Busy);
      Fut.return Busy
  | false -> (
      t.running := true;
      let now = Ptime_clock.now () in
      let* due = due t ~force ~now in
      match due with
      | false ->
          t.running := false;
          Fut.return Not_due
      | true ->
          let+ outcome = safe_check t ~now in
          t.running := false;
          log (outcome_to_string outcome);
          outcome)
