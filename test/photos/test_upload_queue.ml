(* Herbier_photos.Upload_queue (app/photos/upload_queue.mli): the pure
   decision table — session_usable, next, count_failure,
   missing_file and on_network_change — with no IO. Photos are built with
   herbier_test_support's Value, as test_outbox.ml's fixtures do. *)

module Upload_queue = Herbier_photos.Upload_queue
module Drive = Herbier_photos.Drive
module Photo = Herbier_domain.Photo
module Ids = Herbier_domain.Ids
module Value = Herbier_test_support.Value
module Fixture = Herbier_test_support.Fixture

(* ---------- testables ---------- *)

let action_t =
  Alcotest.testable Upload_queue.pp_action Upload_queue.equal_action

(* ---------- fixtures ---------- *)

let time = Value.time
let t0 = time "2026-11-12T10:00:00Z"
let photo_id = Value.id "photo id" Ids.Photo_id.of_string (Value.uuid7 1)

let observation_id =
  Value.id "observation id" Ids.Observation_id.of_string (Value.uuid7 2)

(* Shifts [t0] by [secs] seconds (positive or negative). *)
let shift secs =
  let span = Ptime.Span.of_int_s (abs secs) in
  match
    if secs >= 0 then Ptime.add_span t0 span else Ptime.sub_span t0 span
  with
  | Some t -> t
  | None -> Alcotest.fail "Ptime over/underflow in a test fixture"

let six_days_s = 6 * 24 * 3600

let photo ?(original_target = Photo.Original_target.Drive)
    ?(upload_state = Photo.Upload_state.Pending) () : Photo.t =
  {
    id = photo_id;
    observation_id;
    taken_at = t0;
    width = 1024;
    height = 768;
    sha256 = String.make 64 'a';
    preview_path = "previews/1.webp";
    preview_bucket_key = None;
    original_target;
    drive_file_id = None;
    upload_state;
    created_at = t0;
    updated_at = t0;
    deleted_at = None;
  }

let session ?(created_at = t0) url : Upload_queue.session = {url; created_at}
let usable_session = session ~created_at:t0 "https://example.test/usable"

(* Expired at [t0]: created 6 days before. *)
let expired_session =
  session ~created_at:(shift (-six_days_s)) "https://example.test/expired"

let pending ?(attempts = 0) ?session () : Upload_queue.pending =
  {attempts; session}

(* ---------- constants ---------- *)

let constants_tests =
  [
    ( "max_attempts is 3",
      `Quick,
      fun () -> Alcotest.(check int) "max_attempts" 3 Upload_queue.max_attempts
    );
    ( "session_lifetime is 6 days",
      `Quick,
      fun () ->
        Alcotest.(check (option int))
          "session_lifetime in seconds" (Some six_days_s)
          (Ptime.Span.to_int_s Upload_queue.session_lifetime) );
  ]

(* ---------- session_usable ---------- *)

let session_usable_tests =
  let case name expected ~created ~now =
    ( name,
      `Quick,
      fun () ->
        Alcotest.(check bool)
          "session_usable" expected
          (Upload_queue.session_usable ~now (session ~created_at:created "u"))
    )
  in
  [
    case "created at now: usable" true ~created:t0 ~now:t0;
    case "now, 6 days minus 1 s after created: usable" true ~created:t0
      ~now:(shift (six_days_s - 1));
    case "now, exactly 6 days after created: not usable" false ~created:t0
      ~now:(shift six_days_s);
    case "created 1 s in the future (the clock went back): not usable" false
      ~created:(shift 1) ~now:t0;
  ]

(* ---------- next ---------- *)

let succeeded status body = Upload_queue.Succeeded {status; body}

let answered status body =
  Upload_queue.Failed (Upload_queue.Answered {status; body})

let file_missing = Upload_queue.Failed Upload_queue.File_missing
let gave_up m = Upload_queue.Failed (Upload_queue.Gave_up m)

let finished_body =
  {|{"id":"f1","webViewLink":"https://drive.google.com/file/d/f1/view"}|}

let finished : Drive.file =
  {id = "f1"; web_view_link = Some "https://drive.google.com/file/d/f1/view"}

(* A storageQuotaExceeded 403 body: [fail] turns it into [quota_error]'s
   text. *)
let quota_403_body =
  {|{"error":{"code":403,"errors":[{"reason":"storageQuotaExceeded"}]}}|}

let quota_error = Drive.error_to_string Drive.Quota_full
let unknown_404_body = Fixture.read "drive_session_put_unknown_404.txt"
let next ~now ~photo p job = Upload_queue.next ~now ~photo p job

let next_tests =
  [
    ( "no photo row: Discard",
      `Quick,
      fun () ->
        Alcotest.check action_t "next" Upload_queue.Discard
          (next ~now:t0 ~photo:None (pending ()) None) );
    ( "original_target App_only: Discard",
      `Quick,
      fun () ->
        Alcotest.check action_t "next" Upload_queue.Discard
          (next ~now:t0
             ~photo:(Some (photo ~original_target:App_only ()))
             (pending ()) None) );
    ( "upload_state Uploaded: Discard",
      `Quick,
      fun () ->
        Alcotest.check action_t "next" Upload_queue.Discard
          (next ~now:t0
             ~photo:(Some (photo ~upload_state:Uploaded ()))
             (pending ()) None) );
    ( "upload_state Original_missing: Discard",
      `Quick,
      fun () ->
        Alcotest.check action_t "next" Upload_queue.Discard
          (next ~now:t0
             ~photo:(Some (photo ~upload_state:Original_missing ()))
             (pending ()) None) );
    ( "upload_state Failed, even with a Succeeded job: Nothing (waits for \
       \"Envoyer maintenant\")",
      `Quick,
      fun () ->
        Alcotest.check action_t "next" Upload_queue.Nothing
          (next ~now:t0
             ~photo:(Some (photo ~upload_state:Failed ()))
             (pending ())
             (Some (succeeded 200 finished_body))) );
    ( "job Waiting: Nothing",
      `Quick,
      fun () ->
        Alcotest.check action_t "next" Upload_queue.Nothing
          (next ~now:t0
             ~photo:(Some (photo ()))
             (pending ()) (Some Upload_queue.Waiting)) );
    ( "job Running: Nothing",
      `Quick,
      fun () ->
        Alcotest.check action_t "next" Upload_queue.Nothing
          (next ~now:t0
             ~photo:(Some (photo ()))
             (pending ()) (Some Upload_queue.Running)) );
    ( "job Succeeded 200 with a decodable body: Finish",
      `Quick,
      fun () ->
        Alcotest.check action_t "next" (Upload_queue.Finish finished)
          (next ~now:t0
             ~photo:(Some (photo ()))
             (pending ())
             (Some (succeeded 200 finished_body))) );
    ( "job Succeeded 201 with the same body: Finish",
      `Quick,
      fun () ->
        Alcotest.check action_t "next" (Upload_queue.Finish finished)
          (next ~now:t0
             ~photo:(Some (photo ()))
             (pending ())
             (Some (succeeded 201 finished_body))) );
    ( "job Succeeded 200 with a body that does not decode: Start (the lookup \
       finds it)",
      `Quick,
      fun () ->
        Alcotest.check action_t "next" Upload_queue.Start
          (next ~now:t0
             ~photo:(Some (photo ()))
             (pending ())
             (Some (succeeded 200 "not json"))) );
    ( "job Succeeded 204 (another status): Start",
      `Quick,
      fun () ->
        Alcotest.check action_t "next" Upload_queue.Start
          (next ~now:t0
             ~photo:(Some (photo ()))
             (pending ())
             (Some (succeeded 204 finished_body))) );
    ( "job Failed, Answered 404 (the recorded fixture body), a fresh session: \
       an attempt counted, Retry restarting",
      `Quick,
      fun () ->
        Alcotest.check action_t "next"
          (Upload_queue.Retry
             {
               attempts = 2;
               error =
                 Drive.error_to_string
                   (Drive.error_of_answer ~status:404 ~body:unknown_404_body);
               resume = Restart;
             })
          (next ~now:t0
             ~photo:(Some (photo ()))
             (pending ~attempts:1 ~session:usable_session ())
             (Some (answered 404 unknown_404_body))) );
    ( "same, attempts 2 (one short of max_attempts): Give_up",
      `Quick,
      fun () ->
        Alcotest.check action_t "next"
          (Upload_queue.Give_up
             {
               attempts = 3;
               error =
                 Drive.error_to_string
                   (Drive.error_of_answer ~status:404 ~body:unknown_404_body);
             })
          (next ~now:t0
             ~photo:(Some (photo ()))
             (pending ~attempts:2 ~session:usable_session ())
             (Some (answered 404 unknown_404_body))) );
    ( "job Failed, Answered 410: Retry restarting",
      `Quick,
      fun () ->
        Alcotest.check action_t "next"
          (Upload_queue.Retry
             {
               attempts = 1;
               error =
                 Drive.error_to_string
                   (Drive.error_of_answer ~status:410 ~body:"{}");
               resume = Restart;
             })
          (next ~now:t0
             ~photo:(Some (photo ()))
             (pending ())
             (Some (answered 410 "{}"))) );
    ( "job Failed File_missing, attempts 0: Give_up at once, whatever \
       max_attempts",
      `Quick,
      fun () ->
        Alcotest.check action_t "next"
          (Upload_queue.Give_up {attempts = 1; error = "original file missing"})
          (next ~now:t0
             ~photo:(Some (photo ()))
             (pending ~attempts:0 ()) (Some file_missing)) );
    ( "job Failed, Answered 403 (quota), attempts 0, a usable session: Retry \
       resuming it",
      `Quick,
      fun () ->
        Alcotest.check action_t "next"
          (Upload_queue.Retry
             {attempts = 1; error = quota_error; resume = Resume usable_session})
          (next ~now:t0
             ~photo:(Some (photo ()))
             (pending ~attempts:0 ~session:usable_session ())
             (Some (answered 403 quota_403_body))) );
    ( "same, but the session has expired: Retry restarting",
      `Quick,
      fun () ->
        Alcotest.check action_t "next"
          (Upload_queue.Retry
             {attempts = 1; error = quota_error; resume = Restart})
          (next ~now:t0
             ~photo:(Some (photo ()))
             (pending ~attempts:0 ~session:expired_session ())
             (Some (answered 403 quota_403_body))) );
    ( "same, but attempts is already 2 (one short of max_attempts): Give_up",
      `Quick,
      fun () ->
        Alcotest.check action_t "next"
          (Upload_queue.Give_up {attempts = 3; error = quota_error})
          (next ~now:t0
             ~photo:(Some (photo ()))
             (pending ~attempts:2 ~session:usable_session ())
             (Some (answered 403 quota_403_body))) );
    ( "job Failed (Gave_up \"HTTP 503\"), attempts 0, no session: Retry \
       restarting",
      `Quick,
      fun () ->
        Alcotest.check action_t "next"
          (Upload_queue.Retry
             {attempts = 1; error = "HTTP 503"; resume = Restart})
          (next ~now:t0
             ~photo:(Some (photo ()))
             (pending ~attempts:0 ())
             (Some (gave_up "HTTP 503"))) );
    ( "a failed job still listed, an expired session, three passes on the same \
       saved row (no new job enqueued, so attempts not saved): Retry 1 each \
       time, never Give_up",
      `Quick,
      fun () ->
        let p = pending ~attempts:0 ~session:expired_session () in
        let pass () =
          next ~now:t0 ~photo:(Some (photo ())) p (Some (gave_up "HTTP 503"))
        in
        List.iter
          (fun a ->
            Alcotest.check action_t "next"
              (Upload_queue.Retry
                 {attempts = 1; error = "HTTP 503"; resume = Restart})
              a)
          [pass (); pass (); pass ()] );
    ( "job Cancelled, a usable session: Enqueue it",
      `Quick,
      fun () ->
        Alcotest.check action_t "next" (Upload_queue.Enqueue usable_session)
          (next ~now:t0
             ~photo:(Some (photo ()))
             (pending ~session:usable_session ())
             (Some Upload_queue.Cancelled)) );
    ( "no job, a usable session: Enqueue it (the same rule as Cancelled)",
      `Quick,
      fun () ->
        Alcotest.check action_t "next" (Upload_queue.Enqueue usable_session)
          (next ~now:t0
             ~photo:(Some (photo ()))
             (pending ~session:usable_session ())
             None) );
    ( "no job, no session: Start",
      `Quick,
      fun () ->
        Alcotest.check action_t "next" Upload_queue.Start
          (next ~now:t0 ~photo:(Some (photo ())) (pending ()) None) );
    ( "no job, an expired session: Start",
      `Quick,
      fun () ->
        Alcotest.check action_t "next" Upload_queue.Start
          (next ~now:t0
             ~photo:(Some (photo ()))
             (pending ~session:expired_session ())
             None) );
  ]

(* ---------- count_failure, missing_file ---------- *)

let pp_counted ppf = function
  | Upload_queue.Retry_later {attempts; error} ->
      Format.fprintf ppf "Retry_later %d (%s)" attempts error
  | Upload_queue.Give_up_now {attempts; error} ->
      Format.fprintf ppf "Give_up_now %d (%s)" attempts error

let counted_t = Alcotest.testable pp_counted ( = )

let count_failure_tests =
  [
    ( "attempts 0: Retry_later 1",
      `Quick,
      fun () ->
        Alcotest.check counted_t "count_failure"
          (Upload_queue.Retry_later {attempts = 1; error = "e"})
          (Upload_queue.count_failure (pending ~attempts:0 ()) "e") );
    ( "attempts 2 (one short of max_attempts): Give_up_now 3",
      `Quick,
      fun () ->
        Alcotest.check counted_t "count_failure"
          (Upload_queue.Give_up_now {attempts = 3; error = "e"})
          (Upload_queue.count_failure (pending ~attempts:2 ()) "e") );
    ( "missing_file: attempts + 1, \"original file missing\"",
      `Quick,
      fun () ->
        let c = Upload_queue.missing_file (pending ~attempts:1 ()) in
        Alcotest.(check (pair int string))
          "missing_file"
          (2, "original file missing")
          (c.attempts, c.error) );
  ]

(* ---------- on_network_change ---------- *)

let on_network_change_tests =
  let session_t =
    Alcotest.testable
      (fun ppf (s : Upload_queue.session) -> Format.pp_print_string ppf s.url)
      Upload_queue.equal_session
  in
  let case name ?session job expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.(check (option session_t))
          "on_network_change" expected
          (Upload_queue.on_network_change ~now:t0 (pending ?session ()) job) )
  in
  [
    case "Waiting, a usable session: enqueued again" ~session:usable_session
      (Some Upload_queue.Waiting) (Some usable_session);
    case "Waiting, an expired session: nothing" ~session:expired_session
      (Some Upload_queue.Waiting) None;
    case "Waiting, no session: nothing" (Some Upload_queue.Waiting) None;
    case "Running: finishes on its network" ~session:usable_session
      (Some Upload_queue.Running) None;
    case "Succeeded: the pass's" ~session:usable_session
      (Some (succeeded 200 finished_body))
      None;
    case "Failed: the pass's" ~session:usable_session (Some (gave_up "x")) None;
    case "Cancelled: the pass's" ~session:usable_session
      (Some Upload_queue.Cancelled) None;
    case "no job: the pass's" ~session:usable_session None None;
  ]

(* ---------- retryable ---------- *)

let retryable_tests =
  let case name expected p =
    ( name,
      `Quick,
      fun () ->
        Alcotest.(check bool) "retryable" expected (Upload_queue.retryable p) )
  in
  [
    case "None (absent or deleted): false" false None;
    case "Drive, Failed: true" true (Some (photo ~upload_state:Failed ()));
    case "Drive, Pending: false" false (Some (photo ~upload_state:Pending ()));
    case "Drive, Uploaded: false" false (Some (photo ~upload_state:Uploaded ()));
    case "Drive, Original_missing: false" false
      (Some (photo ~upload_state:Original_missing ()));
    case "App_only, Failed: false" false
      (Some (photo ~original_target:App_only ~upload_state:Failed ()));
  ]

(* ---------- a photo deleted while uploading, and the Drive bin (M8.94) ---------- *)

let deleted_tests =
  let file_body =
    {|{"id":"F9","webViewLink":"https://drive.google.com/file/d/F9/view"}|}
  in
  let f9 =
    {
      Drive.id = "F9";
      web_view_link = Some "https://drive.google.com/file/d/F9/view";
    }
  in
  let case name job expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.check action_t "next" expected
          (next ~now:t0 ~photo:None (pending ()) job) )
  in
  [
    case "deleted, job Succeeded 200: Discard_uploaded of its file"
      (Some (succeeded 200 file_body))
      (Upload_queue.Discard_uploaded f9);
    case "deleted, job Succeeded 201: Discard_uploaded of its file"
      (Some (succeeded 201 file_body))
      (Upload_queue.Discard_uploaded f9);
    case "deleted, job Succeeded with an undecodable body: Discard"
      (Some (succeeded 200 "<html>"))
      Upload_queue.Discard;
    case "deleted, job Succeeded 308: Discard"
      (Some (succeeded 308 ""))
      Upload_queue.Discard;
    case "deleted while still waiting: Discard (its upload cancelled)"
      (Some Upload_queue.Waiting) Upload_queue.Discard;
    case "deleted while running: Discard (its upload cancelled)"
      (Some Upload_queue.Running) Upload_queue.Discard;
    case "deleted, no job: Discard" None Upload_queue.Discard;
    ( "app-only (not deleted), job Succeeded: Discard, nothing trashed",
      `Quick,
      fun () ->
        Alcotest.check action_t "next" Upload_queue.Discard
          (next ~now:t0
             ~photo:(Some (photo ~original_target:App_only ()))
             (pending ())
             (Some (succeeded 200 file_body))) );
    ( "pp_action names the file to trash",
      `Quick,
      fun () ->
        Alcotest.(check string)
          "pp" "discard, trash F9"
          (Format.asprintf "%a" Upload_queue.pp_action
             (Upload_queue.Discard_uploaded f9)) );
  ]

let trash_step_t =
  Alcotest.testable
    (fun ppf s ->
      Format.pp_print_string ppf
        (match (s : Upload_queue.trash_step) with
        | Trash -> "Trash"
        | Forget_trash -> "Forget_trash"
        | Trash_failed -> "Trash_failed"))
    Upload_queue.equal_trash_step

let trash_outcome_t =
  Alcotest.testable
    (fun ppf (o : Upload_queue.trash_outcome) ->
      match o with
      | Trashed -> Format.pp_print_string ppf "Trashed"
      | Blocked e -> Format.fprintf ppf "Blocked %S" e
      | Counted (Retry_later {attempts; error}) ->
          Format.fprintf ppf "Retry_later %d %S" attempts error
      | Counted (Give_up_now {attempts; error}) ->
          Format.fprintf ppf "Give_up_now %d %S" attempts error)
    Upload_queue.equal_trash_outcome

let trash_tests =
  let step ~live ~attempts expected =
    ( Printf.sprintf "trash_next ~live:%b ~attempts:%d" live attempts,
      `Quick,
      fun () ->
        Alcotest.check trash_step_t "trash_next" expected
          (Upload_queue.trash_next ~live ~attempts) )
  in
  let outcome name ~attempts r expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.check trash_outcome_t "trash_outcome" expected
          (Upload_queue.trash_outcome ~attempts r) )
  in
  [
    step ~live:false ~attempts:0 Upload_queue.Trash;
    step ~live:false ~attempts:2 Upload_queue.Trash;
    step ~live:false ~attempts:3 Upload_queue.Trash_failed;
    step ~live:true ~attempts:0 Upload_queue.Forget_trash;
    step ~live:true ~attempts:3 Upload_queue.Forget_trash;
    ( "trash_gave_up at max_attempts",
      `Quick,
      fun () ->
        Alcotest.(check bool) "2" false (Upload_queue.trash_gave_up ~attempts:2);
        Alcotest.(check bool) "3" true (Upload_queue.trash_gave_up ~attempts:3)
    );
    outcome "done (trashed, already in the bin, or 404) is Trashed" ~attempts:1
      (Ok ()) Upload_queue.Trashed;
    outcome "401 is Blocked, not counted" ~attempts:0 (Error Drive.Unauthorized)
      (Upload_queue.Blocked "unauthorized");
    outcome "a missing scope is Blocked" ~attempts:0 (Error Drive.Scope_missing)
      (Upload_queue.Blocked (Drive.error_to_string Drive.Scope_missing));
    outcome "offline (Network) is Blocked" ~attempts:2
      (Error (Drive.Network "timeout"))
      (Upload_queue.Blocked (Drive.error_to_string (Drive.Network "timeout")));
    outcome "a file-only error counts one attempt" ~attempts:0
      (Error
         (Drive.Http
            {
              status = 403;
              reason = Some "appNotAuthorizedToFile";
              message = None;
            }))
      (Upload_queue.Counted
         (Retry_later
            {
              attempts = 1;
              error =
                Drive.error_to_string
                  (Drive.Http
                     {
                       status = 403;
                       reason = Some "appNotAuthorizedToFile";
                       message = None;
                     });
            }));
    outcome "the third file-only error gives up" ~attempts:2
      (Error (Drive.Malformed "trashed"))
      (Upload_queue.Counted
         (Give_up_now
            {
              attempts = 3;
              error = Drive.error_to_string (Drive.Malformed "trashed");
            }));
  ]
