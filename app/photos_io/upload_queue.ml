module Photo = Herbier_domain.Photo
module Photo_id = Herbier_domain.Ids.Photo_id
module Db = Herbier_store_io.Db
module Files = Herbier_store_io.Files
module Uploads = Herbier_store.Uploads
module Photos = Herbier_store.Photos
module Api = Herbier_photos.Drive
module Queue = Herbier_photos.Upload_queue
module Cap_uploader = Herbier_bindings.Cap_uploader
module Cap_error = Herbier_bindings.Cap_error
module Cap_filesystem = Herbier_bindings.Cap_filesystem

(* A pass running: whether another was asked for meanwhile ([Some
   interactive], interactive when any of those calls was), what those calls
   resolve with, and how it is resolved. *)
type pass =
  | Idle
  | Running of {
      again : bool option;
      done_ : unit Fut.t;
      finished : unit -> unit;
    }

type t = {
  db : Db.t;
  commit : Herbier_store.Outbox.edit list -> (int, Db.error) result Fut.t;
  token : interactive:bool -> (string, string) result Fut.t;
  drop_token : string -> unit Fut.t;
  wifi_only : unit -> bool;
  pass : pass ref;
      (* style: mutable because a pass settles in a future's callback; the
         single-flight state, nothing outside this module sees it. *)
  network_changed : bool ref;
      (* style: mutable for the same reason: set by {!wifi_changed}, read and
         cleared by the next pass, which enqueues the waiting jobs again. *)
  retry_failed : bool ref;
      (* style: mutable for the same reason: set by {!send_now}, read and
         cleared by the next pass, which first resets the failed rows. *)
  stop_requested : ((unit, Db.error) result -> unit) list ref;
      (* style: mutable for the same reason: the waiting {!stop_drive} calls,
         answered and cleared by the next pass, which first makes the waiting
         photos app-only. *)
  reset : Photo_id.t list ref;
      (* style: mutable for the same reason: the photos « Envoyer maintenant »
         reset, whose old failed job (WorkManager keeps listing it after a
         cancel) is ignored until a new job replaces it, or the row ends. *)
}

let create ~db ~commit ~token ~drop_token ~wifi_only =
  {
    db;
    commit;
    token;
    drop_token;
    wifi_only;
    pass = ref Idle;
    network_changed = ref false;
    retry_failed = ref false;
    stop_requested = ref [];
    reset = ref [];
  }

let log parts = Brr.Console.(log [str (String.concat " " ("upload:" :: parts))])

let log_error parts =
  Brr.Console.(error [str (String.concat " " ("upload:" :: parts))])

let forget_reset t photo_id =
  t.reset := List.filter (fun id -> not (Photo_id.equal id photo_id)) !(t.reset)

let set_upload t photo_id ~state ~drive_file_id =
  t.commit
    [Photos.set_upload photo_id ~state ~drive_file_id ~at:(Ptime_clock.now ())]

(* Keep *)

type keep_error = Write of Cap_error.t | Store of Db.error

let keep_error_to_string = function
  | Write e -> "original not written: " ^ Cap_error.to_string e
  | Store e -> "upload row not written: " ^ Db.error_to_string e

type kept = Kept | Not_drive

let delete_quietly ~path =
  Fut.map (fun (_ : (unit, Cap_error.t) result) -> ()) (Files.delete ~path)

let write_original t (photo : Photo.t) blob =
  let open Fut.Syntax in
  let path = Files.original photo.id in
  let* written = Files.write_blob ~path blob in
  match written with
  | Error e ->
      let+ () = delete_quietly ~path in
      Error (Write e)
  | Ok () -> (
      let mime =
        match Jstr.to_string (Brr.Blob.type' blob) with
        | "" -> "application/octet-stream"
        | mime -> mime
      in
      let row =
        {
          Uploads.photo_id = photo.id;
          path;
          mime;
          size_bytes = Brr.Blob.byte_length blob;
          session = None;
          attempts = 0;
          last_error = None;
          created_at = Ptime_clock.now ();
        }
      in
      let* stored = Db.write t.db (Uploads.put row) in
      match stored with
      | Ok (_ : int) -> Fut.return (Ok ())
      | Error e ->
          let+ () = delete_quietly ~path in
          Error (Store e))

let keep t (photo : Photo.t) blob =
  let open Fut.Syntax in
  match photo.original_target with
  | App_only -> Fut.return (Ok Not_drive)
  | Drive -> (
      let* written = write_original t photo blob in
      match written with
      | Ok () -> Fut.return (Ok Kept)
      | Error e ->
          let+ failed =
            set_upload t photo.id ~state:Failed ~drive_file_id:None
          in
          (match failed with
          | Ok (_ : int) -> ()
          | Error f ->
              log_error
                [Photo_id.to_string photo.id; "keep:"; Db.error_to_string f]);
          Error e)

let to_queue_session ({url; created_at} : Uploads.session) : Queue.session =
  {url; created_at}

let pending (row : Uploads.t) : Queue.pending =
  {attempts = row.attempts; session = Option.map to_queue_session row.session}

let failure : Cap_uploader.failure -> Queue.failure = function
  | Answered {status; body} -> Answered {status; body}
  | File_missing -> File_missing
  | Gave_up m -> Gave_up m

let job : Cap_uploader.state -> Queue.job = function
  | Enqueued | Blocked -> Waiting
  | Running -> Running
  | Succeeded {status; body} -> Succeeded {status; body}
  | Failed f -> Failed (failure f)
  | Cancelled -> Cancelled

let job_of jobs id =
  let id = Photo_id.to_string id in
  List.find_opt (fun (j : Cap_uploader.job) -> String.equal j.id id) jobs

(* The pass *)

(* Whether this pass may still start sessions: a token or account-wide Drive
   error closes it for every later row. *)
type gate = Open | Closed

let id_string (row : Uploads.t) = Photo_id.to_string row.photo_id

let write_row t (row : Uploads.t) =
  Fut.map
    (function
      | Ok (_ : int) -> ()
      | Error e -> log_error [id_string row; "row:"; Db.error_to_string e])
    (Db.write t.db (Uploads.put row))

let delete_file (row : Uploads.t) =
  Fut.map
    (function
      | Ok () -> ()
      | Error e when Cap_filesystem.is_missing e -> ()
      | Error e -> log_error [id_string row; "file:"; Cap_error.to_string e])
    (Files.delete ~path:row.path)

let forget t (row : Uploads.t) =
  let open Fut.Syntax in
  forget_reset t row.photo_id;
  let* removed = Db.write t.db (Uploads.remove row.photo_id) in
  match removed with
  | Error e ->
      Fut.return (log_error [id_string row; "row:"; Db.error_to_string e])
  | Ok (_ : int) -> delete_file row

let discard t (row : Uploads.t) =
  let open Fut.Syntax in
  let* cancelled = Cap_uploader.cancel ~id:(id_string row) in
  (match cancelled with
  | Ok () -> ()
  | Error e -> log_error [id_string row; "cancel:"; Cap_error.to_string e]);
  forget t row

let finish t (row : Uploads.t) (file : Api.file) =
  let open Fut.Syntax in
  let* committed =
    set_upload t row.photo_id ~state:Uploaded ~drive_file_id:(Some file.id)
  in
  match committed with
  | Error e ->
      Fut.return (log_error [id_string row; "finish:"; Db.error_to_string e])
  | Ok (_ : int) ->
      let* written =
        Db.write t.db
          (Herbier_store.Settings.set Last_upload_at (Ptime_clock.now ()))
      in
      (match written with
      | Ok (_ : int) -> ()
      | Error e ->
          log_error [id_string row; "last upload:"; Db.error_to_string e]);
      forget t row

let give_up t (row : Uploads.t) ~attempts ~error =
  let open Fut.Syntax in
  forget_reset t row.photo_id;
  let* () = write_row t {row with attempts; last_error = Some error} in
  let+ committed =
    set_upload t row.photo_id ~state:Failed ~drive_file_id:None
  in
  match committed with
  | Ok (_ : int) -> ()
  | Error e -> log_error [id_string row; "give up:"; Db.error_to_string e]

(* One more failed attempt, the session dropped: the next pass starts
   again, or the photo goes [Failed]. *)
let count_failure t (row : Uploads.t) error =
  match Queue.count_failure (pending row) error with
  | Give_up_now {attempts; error} -> give_up t row ~attempts ~error
  | Retry_later {attempts; error} ->
      write_row t {row with attempts; last_error = Some error; session = None}

(* [attempts] is written only once the new job is enqueued (see {!Queue.next}). *)
let enqueue t (row : Uploads.t) ~attempts (session : Queue.session) =
  let open Fut.Syntax in
  let network : Cap_uploader.network =
    match t.wifi_only () with true -> Unmetered | false -> Any
  in
  let* enqueued =
    Cap_uploader.enqueue ~id:(id_string row) ~path:row.path ~url:session.url
      ~mime:row.mime ~network
  in
  match enqueued with
  | Ok () -> (
      forget_reset t row.photo_id;
      match attempts = row.attempts with
      | true -> Fut.return ()
      | false -> write_row t {row with attempts})
  | Error (Rejected {code = Some "FILE_NOT_FOUND"; _}) ->
      let {Queue.attempts; error} = Queue.missing_file (pending row) in
      log [id_string row; "give up"; error];
      give_up t row ~attempts ~error
  | Error (Rejected {code = Some "INVALID_ARGUMENT"; message}) ->
      log_error [id_string row; "enqueue rejected:"; message];
      count_failure t row ("enqueue rejected: " ^ message)
  | Error e ->
      let error = Cap_error.to_string e in
      log_error [id_string row; "enqueue:"; error];
      write_row t {row with last_error = Some ("enqueue: " ^ error)}

let target t (row : Uploads.t) (photo : Photo.t) =
  let open Fut.Result_syntax in
  let* observation =
    Db.find t.db (Herbier_store.Observations.get photo.observation_id)
  in
  let+ plant =
    match
      Option.bind observation (fun (o : Herbier_domain.Observation.t) ->
          o.plant_id)
    with
    | None -> Fut.return (Ok None)
    | Some plant -> Db.find t.db (Herbier_store.Plants.get plant)
  in
  {
    Api.species = Api.species_folder plant;
    name =
      Api.file_name ~taken_at:photo.taken_at
        ~offset_s:
          (Herbier_bindings.Js_date.offset_at_s
             (Ptime.to_float_s photo.taken_at))
        ~id:photo.id ~mime:row.mime;
    mime = row.mime;
    photo_id = photo.id;
    sha256 = photo.sha256;
  }

let start t ~interactive ~attempts (row : Uploads.t) photo =
  let open Fut.Syntax in
  let* target = target t row photo in
  match target with
  | Error e ->
      log_error [id_string row; "start:"; Db.error_to_string e];
      Fut.return Open
  | Ok target -> (
      let* started =
        Drive.start_session
          ~token:(fun () -> t.token ~interactive)
          ~drop_token:t.drop_token target
      in
      match started with
      | Ok (Already_there file) ->
          log [id_string row; "already there"; file.id];
          let+ () = finish t row file in
          Open
      | Ok (Session url) ->
          log [id_string row; "session started"];
          let session = {Uploads.url; created_at = Ptime_clock.now ()} in
          let row = {row with session = Some session} in
          let* () = write_row t row in
          let+ () = enqueue t row ~attempts (to_queue_session session) in
          Open
      | Error (Token e) ->
          log [id_string row; "no token:"; e];
          Fut.return Closed
      | Error (Drive e) -> (
          let error = Api.error_to_string e in
          log [id_string row; "start:"; error];
          match Api.error_scope e with
          | Account ->
              let+ () = write_row t {row with last_error = Some error} in
              Closed
          | This_file ->
              (* Counted from the saved row: a failed job this start was to
                 replace is still listed, and the next pass counts it again.
                 That pass starts again, not this one. *)
              let+ () = count_failure t row error in
              Open))

let start_if_open t ~interactive ~attempts gate row photo =
  match (gate, photo) with
  | Closed, _ | Open, None -> Fut.return gate
  | Open, Some photo -> start t ~interactive ~attempts row photo

let act t ~interactive gate (row : Uploads.t) photo action =
  let open Fut.Syntax in
  match (action : Queue.action) with
  | Nothing -> Fut.return gate
  | Discard ->
      let+ () = discard t row in
      gate
  | Finish file ->
      let+ () = finish t row file in
      gate
  | Give_up {attempts; error} ->
      let+ () = give_up t row ~attempts ~error in
      gate
  | Enqueue session ->
      let+ () = enqueue t row ~attempts:row.attempts session in
      gate
  | Start -> start_if_open t ~interactive ~attempts:row.attempts gate row photo
  | Retry {attempts; error; resume = Resume session} ->
      let row = {row with last_error = Some error} in
      let* () = write_row t row in
      let+ () = enqueue t row ~attempts session in
      gate
  | Retry {attempts; error; resume = Restart} ->
      let row = {row with last_error = Some error; session = None} in
      let* () = write_row t row in
      start_if_open t ~interactive ~attempts gate row photo

(* After « Envoyer seulement en Wi-Fi » changed: a waiting job enqueued again
   under the new constraint, in place of the pass's own action (which, for a
   waiting job, is [Nothing] or [Discard]). *)
let rewire t ~now (row : Uploads.t) job action =
  match (action : Queue.action) with
  | Nothing -> (
      match Queue.on_network_change ~now (pending row) job with
      | Some session ->
          log [id_string row; "enqueue (network changed)"];
          Some (enqueue t row ~attempts:row.attempts session)
      | None -> None)
  | Start | Enqueue _ | Finish _ | Retry _ | Give_up _ | Discard -> None

let step t ~interactive ~network_changed ~jobs gate (row : Uploads.t) =
  let open Fut.Syntax in
  let* photo = Db.find t.db (Photos.get row.photo_id) in
  match photo with
  | Error e ->
      log_error [id_string row; "photo:"; Db.error_to_string e];
      Fut.return gate
  | Ok photo -> (
      let job =
        match List.exists (Photo_id.equal row.photo_id) !(t.reset) with
        | true ->
            (* Its failed job was cancelled by « Envoyer maintenant »; a
               finished job stays listed as failed, and must not be counted
               again. *)
            None
        | false ->
            Option.map
              (fun (j : Cap_uploader.job) -> job j.state)
              (job_of jobs row.photo_id)
      in
      let now = Ptime_clock.now () in
      let action = Queue.next ~now ~photo (pending row) job in
      let rewired =
        match network_changed with
        | true -> rewire t ~now row job action
        | false -> None
      in
      match rewired with
      | Some enqueued ->
          let+ () = enqueued in
          gate
      | None ->
          (match action with
          | Nothing -> ()
          | Start | Enqueue _ | Finish _ | Retry _ | Give_up _ | Discard ->
              log [id_string row; Format.asprintf "%a" Queue.pp_action action]);
          act t ~interactive gate row photo action)

(* Before a pass: the rows and their live photos; the first read error. *)
let rows_with_photos t =
  let open Fut.Syntax in
  let* rows = Db.all t.db Uploads.all in
  match rows with
  | Error e -> Fut.return (Error e)
  | Ok rows ->
      List.fold_right
        (fun (row : Uploads.t) acc ->
          let* acc = acc in
          match acc with
          | Error _ -> Fut.return acc
          | Ok acc -> (
              let+ photo = Db.find t.db (Photos.get row.photo_id) in
              match photo with
              | Error e -> Error e
              | Ok photo -> Ok ((row, photo) :: acc)))
        rows (Fut.return (Ok []))

let commit_edits t edits =
  match edits with
  | [] -> Fut.return (Ok ())
  | edits -> Fut.map (Result.map (fun (_ : int) -> ())) (t.commit edits)

(* « Ne pas les envoyer »: the photos still waiting become app-only, which the
   pass then discards. *)
let make_app_only t =
  let open Fut.Result_syntax in
  let* rows = rows_with_photos t in
  let now = Ptime_clock.now () in
  let waiting =
    List.filter_map
      (fun ((row : Uploads.t), photo) ->
        match photo with
        | Some p when Photo.awaiting_drive p -> Some row
        | Some _ | None -> None)
      rows
  in
  List.iter (fun row -> log [id_string row; "app-only"]) waiting;
  commit_edits t
    (List.map
       (fun (row : Uploads.t) -> Photos.set_app_only row.photo_id ~at:now)
       waiting)

let reset_row t (row : Uploads.t) =
  let open Fut.Syntax in
  let* cancelled = Cap_uploader.cancel ~id:(id_string row) in
  (match cancelled with
  | Ok () -> ()
  | Error e -> log_error [id_string row; "cancel:"; Cap_error.to_string e]);
  log [id_string row; "reset"];
  write_row t {row with attempts = 0; last_error = None}

(* « Envoyer maintenant »: the failed photos' rows reset, the photos back to
   [Pending]; their ids join [t.reset]. *)
let reset_failed t =
  let open Fut.Syntax in
  let* rows = rows_with_photos t in
  let rows =
    match rows with
    | Ok rows -> rows
    | Error e ->
        log_error ["reset:"; Db.error_to_string e];
        []
  in
  let failed =
    List.filter_map
      (fun (row, photo) ->
        match Queue.retryable photo with true -> Some row | false -> None)
      rows
  in
  let* () =
    List.fold_left
      (fun acc row -> Fut.bind acc (fun () -> reset_row t row))
      (Fut.return ()) failed
  in
  let now = Ptime_clock.now () in
  let+ committed =
    commit_edits t
      (List.map
         (fun (row : Uploads.t) ->
           Photos.set_upload row.photo_id ~state:Pending ~drive_file_id:None
             ~at:now)
         failed)
  in
  (match committed with
  | Ok () -> ()
  | Error e -> log_error ["reset:"; Db.error_to_string e]);
  t.reset :=
    List.map (fun (row : Uploads.t) -> row.photo_id) failed
    @ List.filter
        (fun id ->
          not
            (List.exists
               (fun (row : Uploads.t) -> Photo_id.equal id row.photo_id)
               failed))
        !(t.reset)

let stop t answers =
  let open Fut.Syntax in
  match answers with
  | [] -> Fut.return ()
  | answers ->
      let+ result = make_app_only t in
      (match result with
      | Ok () -> ()
      | Error e -> log_error ["app-only:"; Db.error_to_string e]);
      List.iter (fun answer -> answer result) answers

let prepare t ~stop:answers ~retry =
  let open Fut.Syntax in
  let* () = stop t answers in
  match retry with true -> reset_failed t | false -> Fut.return ()

let pass t ~interactive =
  let open Fut.Syntax in
  let stop = !(t.stop_requested) and retry = !(t.retry_failed) in
  t.stop_requested := [];
  t.retry_failed := false;
  let* () = prepare t ~stop ~retry in
  let* jobs = Cap_uploader.jobs () in
  match jobs with
  | Error e -> Fut.return (log ["jobs:"; Cap_error.to_string e])
  | Ok jobs -> (
      let* rows = Db.all t.db Uploads.all in
      match rows with
      | Error e -> Fut.return (log_error ["rows:"; Db.error_to_string e])
      | Ok rows ->
          let network_changed = !(t.network_changed) in
          t.network_changed := false;
          let+ (_ : gate) =
            List.fold_left
              (fun acc row ->
                Fut.bind acc (fun gate ->
                    step t ~interactive ~network_changed ~jobs gate row))
              (Fut.return Open) rows
          in
          ())

(* A raise before the pass's first future would leave the single-flight state
   Running for good: it is logged and the pass ends. A raise in a later
   continuation is not caught here (Fut has no rejection handler): the pass
   relies on its continuations being total, results and no exceptions. *)
let safe_pass t ~interactive =
  let stop = !(t.stop_requested) in
  match pass t ~interactive with
  | fut -> fut
  | exception ((Failure _ | Invalid_argument _ | Not_found | Jv.Error _) as e)
    ->
      let raised = Printexc.to_string e in
      log_error ["pass:"; raised];
      t.stop_requested := [];
      List.iter (fun answer -> answer (Error (Db.Raised raised))) stop;
      Fut.return ()

let run t ~interactive =
  match !(t.pass) with
  | Running r ->
      let again = Some (interactive || Option.value r.again ~default:false) in
      t.pass := Running {r with again};
      r.done_
  | Idle ->
      let done_, finished = Fut.create () in
      t.pass := Running {again = None; done_; finished};
      let rec loop interactive =
        Fut.await (safe_pass t ~interactive) (fun () ->
            match !(t.pass) with
            | Running ({again = Some interactive; _} as r) ->
                t.pass := Running {r with again = None};
                loop interactive
            | Running {again = None; finished; _} ->
                t.pass := Idle;
                finished ()
            | Idle -> ())
      in
      loop interactive;
      done_

let wifi_changed t =
  t.network_changed := true;
  run t ~interactive:false

let send_now t =
  t.retry_failed := true;
  run t ~interactive:true

let stop_drive t =
  let result, answer = Fut.create () in
  t.stop_requested := answer :: !(t.stop_requested);
  let open Fut.Syntax in
  let* () = run t ~interactive:false in
  result

type entry = {
  row : Uploads.t;
  photo : Photo.Upload_state.t option;
  job : Cap_uploader.job option;
}

let entries t =
  let open Fut.Syntax in
  let* jobs = Cap_uploader.jobs () in
  let jobs = Result.value jobs ~default:[] in
  let* rows = Db.all t.db Uploads.all in
  match rows with
  | Error e -> Fut.return (Error e)
  | Ok rows ->
      List.fold_right
        (fun (row : Uploads.t) acc ->
          let* acc = acc in
          match acc with
          | Error _ -> Fut.return acc
          | Ok entries -> (
              let+ photo = Db.find t.db (Photos.get row.photo_id) in
              match photo with
              | Error e -> Error e
              | Ok photo ->
                  Ok
                    ({
                       row;
                       photo =
                         Option.map (fun (p : Photo.t) -> p.upload_state) photo;
                       job = job_of jobs row.photo_id;
                     }
                    :: entries)))
        rows (Fut.return (Ok []))
