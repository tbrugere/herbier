(* Herbier_photos.Health (app/photos/health.mli): due, the items a photo
   list gives, the verdict table, the program over a fake
   network (as test_drive.ml runs Drive programs), and summary. *)

module Health = Herbier_photos.Health
module Drive = Herbier_photos.Drive
module Photo = Herbier_domain.Photo
module Ids = Herbier_domain.Ids
module Value = Herbier_test_support.Value
module Fixture = Herbier_test_support.Fixture
module Text = Herbier_test_support.Text

let fixture name = Fixture.read ("drive_" ^ name ^ ".json")

(* ---------- testables ---------- *)

let pp_request ppf (r : Drive.request) =
  Format.fprintf ppf "%s %s"
    (match r.meth with `GET -> "GET" | `POST -> "POST")
    r.url

let request_t = Alcotest.testable pp_request Drive.equal_request

let pp_item ppf (i : Health.item) =
  Format.fprintf ppf "{photo_id = %s; file_id = %S; state = %s; unsure = %b}"
    (Ids.Photo_id.to_string i.photo_id)
    i.file_id
    (Photo.Upload_state.to_string i.state)
    i.missing_unsure

let item_t = Alcotest.testable pp_item Health.equal_item

let pp_change ppf (c : Health.change) =
  Format.fprintf ppf "{item = %a; state = %s}" pp_item c.item
    (Photo.Upload_state.to_string c.state)

let change_t = Alcotest.testable pp_change Health.equal_change

let pp_skipped ppf (i, e) =
  Format.fprintf ppf "(%a, %s)" pp_item i (Drive.error_to_string e)

let pp_report ppf (r : Health.report) =
  Format.fprintf ppf
    "{checked = %d; changes = %a; skipped = %a; stopped = %s; reached = %s}"
    r.checked
    (Format.pp_print_list pp_change)
    r.changes
    (Format.pp_print_list pp_skipped)
    r.skipped
    (match r.stopped with
    | None -> "None"
    | Some e -> "Some " ^ Drive.error_to_string e)
    (match r.reached with
    | None -> "None"
    | Some id -> "Some " ^ Ids.Photo_id.to_string id)

let report_t = Alcotest.testable pp_report Health.equal_report

let upload_state_t =
  Alcotest.testable
    (fun f s -> Format.pp_print_string f (Photo.Upload_state.to_string s))
    Photo.Upload_state.equal

(* ---------- id and time helpers ---------- *)

let photo_id n = Value.id "photo id" Ids.Photo_id.of_string (Value.uuid7 n)

let observation_id =
  Value.id "observation id" Ids.Observation_id.of_string (Value.uuid7 90)

let t0 = Value.time "2026-11-01T00:00:00Z"

let shift secs =
  let span = Ptime.Span.of_int_s (abs secs) in
  match
    if secs >= 0 then Ptime.add_span t0 span else Ptime.sub_span t0 span
  with
  | Some t -> t
  | None -> Alcotest.fail "Ptime over/underflow in a test fixture"

(* A photo as Health.items reads it: the fields that matter are target,
   state and file_id; the rest are filler. *)
let photo ?(target = Photo.Original_target.Drive)
    ?(state = Photo.Upload_state.Pending) ?(file_id = None) ?deleted_at n :
    Photo.t =
  {
    id = photo_id n;
    observation_id;
    taken_at = t0;
    width = 1024;
    height = 768;
    sha256 = String.make 64 'a';
    preview_path = Printf.sprintf "previews/%d.webp" n;
    preview_bucket_key = None;
    original_target = target;
    drive_file_id = file_id;
    upload_state = state;
    created_at = t0;
    updated_at = t0;
    deleted_at;
  }

let item ?(missing_unsure = false) n file_id state : Health.item =
  {Health.photo_id = photo_id n; file_id; state; missing_unsure}

(* ---------- interval / due ---------- *)

let interval_tests =
  [
    ( "interval is 7 days",
      `Quick,
      fun () ->
        Alcotest.(check (option int))
          "interval in seconds"
          (Some (7 * 24 * 3600))
          (Ptime.Span.to_int_s Health.interval) );
  ]

let due_tests =
  let case name expected ~last =
    ( name,
      `Quick,
      fun () -> Alcotest.(check bool) "due" expected (Health.due ~now:t0 ~last)
    )
  in
  [
    case "last = None: due" true ~last:None;
    case "6 d 23 h 59 min ago: not due" false
      ~last:(Some (shift (-((6 * 24 * 3600) + (23 * 3600) + (59 * 60)))));
    case "exactly 7 days ago: due" true ~last:(Some (shift (-(7 * 24 * 3600))));
    case "30 days ago: due" true ~last:(Some (shift (-(30 * 24 * 3600))));
    case "last 1 h after now (the clock went back): due" true
      ~last:(Some (shift 3600));
  ]

(* ---------- items ---------- *)

let items_tests =
  [
    ( "keeps Drive/Uploaded and Drive/Original_missing with a non-blank, \
       trimmed file id, in input order; drops Pending, Failed, App_only, no \
       file id, a blank file id and a soft-deleted photo",
      `Quick,
      fun () ->
        let kept_uploaded =
          photo ~target:Drive ~state:Uploaded ~file_id:(Some "f1") 1
        in
        let kept_missing =
          photo ~target:Drive ~state:Original_missing ~file_id:(Some "f2") 2
        in
        let pending = photo ~target:Drive ~state:Pending ~file_id:(Some "f3x") 3
        and failed = photo ~target:Drive ~state:Failed ~file_id:(Some "f4") 4
        and app_only =
          photo ~target:App_only ~state:Uploaded ~file_id:(Some "f5") 5
        and no_file_id = photo ~target:Drive ~state:Uploaded ~file_id:None 6
        and blank_file_id =
          photo ~target:Drive ~state:Uploaded ~file_id:(Some "") 7
        and whitespace_file_id =
          photo ~target:Drive ~state:Uploaded ~file_id:(Some "  ") 8
        and deleted =
          photo ~target:Drive ~state:Uploaded ~file_id:(Some "f9")
            ~deleted_at:t0 9
        and kept_trimmed =
          photo ~target:Drive ~state:Uploaded ~file_id:(Some " f3 ") 10
        in
        Alcotest.(check (list item_t))
          "items"
          [
            item 1 "f1" Uploaded;
            item 2 "f2" Original_missing;
            item 10 "f3" Uploaded;
          ]
          (Health.items ~account_changed_at:None
             [
               kept_uploaded;
               kept_missing;
               pending;
               failed;
               app_only;
               no_file_id;
               blank_file_id;
               whitespace_file_id;
               deleted;
               kept_trimmed;
             ]) );
  ]

(* ---------- verdict ---------- *)

(* Photos created before the Drive account last changed may be in the other
   account's Drive: their items are missing_unsure. *)
let account_change_items_tests =
  let uploaded = photo ~target:Drive ~state:Uploaded ~file_id:(Some "f1") 1 in
  let case name account_changed_at expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.(check (list item_t))
          "items" expected
          (Health.items ~account_changed_at [uploaded]) )
  in
  [
    case "no account change: sure" None [item 1 "f1" Uploaded];
    case "created before the change: unsure"
      (Some (shift 60))
      [item ~missing_unsure:true 1 "f1" Uploaded];
    case "created after the change: sure"
      (Some (shift (-60)))
      [item 1 "f1" Uploaded];
    case "created at the change itself: sure" (Some t0) [item 1 "f1" Uploaded];
  ]

let verdict_tests =
  let case name state presence expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.(check (option upload_state_t))
          "verdict" expected
          (Health.verdict state presence) )
  in
  Photo.Upload_state.
    [
      case "Pending, Present: None" Pending Drive.Present None;
      case "Pending, Trashed: None" Pending Drive.Trashed None;
      case "Pending, Missing: None" Pending Drive.Missing None;
      case "Uploaded, Present: None" Uploaded Drive.Present None;
      case "Uploaded, Trashed: Some Original_missing" Uploaded Drive.Trashed
        (Some Original_missing);
      case "Uploaded, Missing: Some Original_missing" Uploaded Drive.Missing
        (Some Original_missing);
      case "Failed, Present: None" Failed Drive.Present None;
      case "Failed, Trashed: None" Failed Drive.Trashed None;
      case "Failed, Missing: None" Failed Drive.Missing None;
      case "Original_missing, Present: Some Uploaded" Original_missing
        Drive.Present (Some Uploaded);
      case "Original_missing, Trashed: None" Original_missing Drive.Trashed None;
      case "Original_missing, Missing: None" Original_missing Drive.Missing None;
    ]

(* ---------- program, over a fake sequential network (as test_drive.ml) ---------- *)

let seq_net (responses : Drive.response list) : Drive.request -> Drive.response
    =
  let remaining = ref responses in
  fun (_ : Drive.request) ->
    match !remaining with
    | [] -> Alcotest.fail "seq_net: no more responses recorded"
    | r :: rest ->
        remaining := rest;
        r

let answer ?(status = 200) ?(headers = []) body : Drive.response =
  Drive.Answer {status; headers; body}

let check_requests msg expected reqs =
  Alcotest.(check (list request_t)) msg expected reqs

let i1 = item 1 "f1" Photo.Upload_state.Uploaded
let i2 = item 2 "f2" Photo.Upload_state.Uploaded
let i3 = item 3 "f3" Photo.Upload_state.Uploaded

let no_token_403_error =
  Drive.Http
    {
      status = 403;
      reason = Some "forbidden";
      message = Some "Permission denied on the service.";
    }

let program_tests =
  [
    ( "the empty list: empty_report, no request",
      `Quick,
      fun () ->
        let prog = Health.program [] in
        check_requests "no request" [] (Drive.requests (seq_net []) prog);
        Alcotest.check report_t "report" Health.empty_report
          (Drive.run (seq_net []) prog) );
    ( "present, trashed, 404 (f2 and f3 were Uploaded): checked 3, two \
       changes, the three get_trashed requests in order",
      `Quick,
      fun () ->
        let prog = Health.program [i1; i2; i3] in
        let responses =
          [
            answer {|{"id":"f1","trashed":false}|};
            answer {|{"id":"f2","trashed":true}|};
            answer ~status:404 "{}";
          ]
        in
        check_requests "three get_trashed requests, in order"
          [
            Drive.get_trashed ~file_id:"f1";
            Drive.get_trashed ~file_id:"f2";
            Drive.get_trashed ~file_id:"f3";
          ]
          (Drive.requests (seq_net responses) prog);
        Alcotest.check report_t "report"
          {
            Health.checked = 3;
            changes =
              [
                {Health.item = i2; state = Original_missing};
                {Health.item = i3; state = Original_missing};
              ];
            skipped = [];
            stopped = None;
            reached = Some i3.photo_id;
          }
          (Drive.run (seq_net responses) prog) );
    ( "an Original_missing item answered present: change to Uploaded",
      `Quick,
      fun () ->
        let missing = item 4 "f4" Photo.Upload_state.Original_missing in
        let prog = Health.program [missing] in
        let responses = [answer {|{"id":"f4","trashed":false}|}] in
        Alcotest.check report_t "report"
          {
            Health.checked = 1;
            changes = [{Health.item = missing; state = Uploaded}];
            skipped = [];
            stopped = None;
            reached = Some missing.photo_id;
          }
          (Drive.run (seq_net responses) prog) );
    ( "item 2 answers 418 with an empty body (Http, This_file): skipped, item \
       3 still asked, checked 2, reached item 3",
      `Quick,
      fun () ->
        let prog = Health.program [i1; i2; i3] in
        let responses =
          [
            answer {|{"id":"f1","trashed":false}|};
            answer ~status:418 "";
            answer {|{"id":"f3","trashed":false}|};
          ]
        in
        check_requests "f1, f2 then f3"
          [
            Drive.get_trashed ~file_id:"f1";
            Drive.get_trashed ~file_id:"f2";
            Drive.get_trashed ~file_id:"f3";
          ]
          (Drive.requests (seq_net responses) prog);
        Alcotest.check report_t "report"
          {
            Health.checked = 2;
            changes = [];
            skipped =
              [(i2, Drive.Http {status = 418; reason = None; message = None})];
            stopped = None;
            reached = Some i3.photo_id;
          }
          (Drive.run (seq_net responses) prog) );
    ( "item 2 answers 401 (recorded body): stopped Unauthorized, item 3 never \
       requested, checked 1",
      `Quick,
      fun () ->
        let prog = Health.program [i1; i2; i3] in
        let responses =
          [
            answer {|{"id":"f1","trashed":false}|};
            answer ~status:401 (fixture "files_get_invalid_token_401");
          ]
        in
        check_requests "f1 and f2, then stops"
          [Drive.get_trashed ~file_id:"f1"; Drive.get_trashed ~file_id:"f2"]
          (Drive.requests (seq_net responses) prog);
        Alcotest.check report_t "report"
          {
            Health.checked = 1;
            changes = [];
            skipped = [];
            stopped = Some Drive.Unauthorized;
            reached = Some i1.photo_id;
          }
          (Drive.run (seq_net responses) prog) );
    ( "the only item answers 403 (recorded, no-token body): skipped with that \
       file's class, 1 request, nothing stopped",
      `Quick,
      fun () ->
        (* a 403 decodes as Http: This_file, so skipped, not stopped *)
        let prog = Health.program [i1] in
        let body = fixture "files_get_no_token_403" in
        let responses = [answer ~status:403 body] in
        let reqs = Drive.requests (seq_net responses) prog in
        Alcotest.(check int) "one request" 1 (List.length reqs);
        Alcotest.check report_t "report"
          {
            Health.checked = 0;
            changes = [];
            skipped = [(i1, no_token_403_error)];
            stopped = None;
            reached = Some i1.photo_id;
          }
          (Drive.run (seq_net responses) prog) );
    ( "an unreachable network: stopped Network \"timeout\"",
      `Quick,
      fun () ->
        let prog = Health.program [i1] in
        Alcotest.check report_t "report"
          {
            Health.checked = 0;
            changes = [];
            skipped = [];
            stopped = Some (Drive.Network "timeout");
            reached = None;
          }
          (Drive.run (seq_net [Drive.Unreachable "timeout"]) prog) );
    ( "the recorded present/trashed/unknown fixtures (user's run of \
       scripts/record-drive-fixtures.sh with HERBIER_DRIVE_TOKEN), when \
       present, give the same three-item case; skipped otherwise",
      `Quick,
      fun () ->
        match
          List.for_all Fixture.exists
            [
              "drive_files_get_present_200.json";
              "drive_files_get_trashed_200.json";
              "drive_files_get_unknown_404.json";
            ]
        with
        | false -> ()
        | true ->
            let prog = Health.program [i1; i2; i3] in
            let responses =
              [
                answer (Fixture.read "drive_files_get_present_200.json");
                answer (Fixture.read "drive_files_get_trashed_200.json");
                answer ~status:404
                  (Fixture.read "drive_files_get_unknown_404.json");
              ]
            in
            Alcotest.check report_t "report"
              {
                Health.checked = 3;
                changes =
                  [
                    {Health.item = i2; state = Original_missing};
                    {Health.item = i3; state = Original_missing};
                  ];
                skipped = [];
                stopped = None;
                reached = Some i3.photo_id;
              }
              (Drive.run (seq_net responses) prog) );
  ]

(* ---------- resume ---------- *)

(* A 404 for an unsure item may be the other account's file: no change. A
   trashed or present answer means the current token reaches the file, so it
   is a verdict as for any item. *)
let unsure_program_tests =
  let run item response =
    Drive.run (seq_net [response]) (Health.program [item])
  in
  let report ~changes item =
    {
      Health.checked = 1;
      changes;
      skipped = [];
      stopped = None;
      reached = Some item.Health.photo_id;
    }
  in
  [
    ( "unsure, Uploaded, 404: answered, no change",
      `Quick,
      fun () ->
        let i = item ~missing_unsure:true 1 "f1" Uploaded in
        Alcotest.check report_t "report" (report ~changes:[] i)
          (run i (answer ~status:404 "{}")) );
    ( "unsure, Uploaded, trashed: Original_missing",
      `Quick,
      fun () ->
        let i = item ~missing_unsure:true 1 "f1" Uploaded in
        Alcotest.check report_t "report"
          (report ~changes:[{Health.item = i; state = Original_missing}] i)
          (run i (answer {|{"id":"f1","trashed":true}|})) );
    ( "unsure, Original_missing, present: Uploaded",
      `Quick,
      fun () ->
        let i = item ~missing_unsure:true 1 "f1" Original_missing in
        Alcotest.check report_t "report"
          (report ~changes:[{Health.item = i; state = Uploaded}] i)
          (run i (answer {|{"id":"f1","trashed":false}|})) );
  ]

let resume_tests =
  let items_t = Alcotest.list item_t in
  let case name after items expected =
    ( name,
      `Quick,
      fun () ->
        Alcotest.check items_t "resume" expected (Health.resume ~after items) )
  in
  [
    case "no cursor: every item" None [i1; i2; i3] [i1; i2; i3];
    case "after item 1: items 2 and 3" (Some i1.photo_id) [i1; i2; i3] [i2; i3];
    case "after the last item: none" (Some i3.photo_id) [i1; i2; i3] [];
    case "a cursor whose photo is gone: the items after its id"
      (Some i2.photo_id) [i1; i3] [i3];
    case "a cursor before every item: all"
      (Some (photo_id 0))
      [i1; i2; i3] [i1; i2; i3];
  ]

(* ---------- summary ---------- *)

let summary_tests =
  [
    ( "checked, changed and skipped counts, no stop",
      `Quick,
      fun () ->
        let report : Health.report =
          {
            checked = 3;
            changes =
              [
                {Health.item = i2; state = Original_missing};
                {Health.item = i3; state = Original_missing};
              ];
            skipped = [];
            stopped = None;
            reached = None;
          }
        in
        Alcotest.(check string)
          "summary" "checked 3, changed 2, skipped 0" (Health.summary report) );
    ( "a stop appends \", stopped: unauthorized\"",
      `Quick,
      fun () ->
        let report : Health.report =
          {
            checked = 1;
            changes = [];
            skipped = [];
            stopped = Some Drive.Unauthorized;
            reached = None;
          }
        in
        Alcotest.(check string)
          "summary" "checked 1, changed 0, skipped 0, stopped: unauthorized"
          (Health.summary report) );
    ( "never contains a file id",
      `Quick,
      fun () ->
        let report : Health.report =
          {
            checked = 1;
            changes = [{Health.item = i1; state = Original_missing}];
            skipped = [(i2, Drive.Not_found)];
            stopped = Some Drive.Unauthorized;
            reached = Some i2.photo_id;
          }
        in
        let s = Health.summary report in
        Alcotest.(check string)
          "summary" "checked 1, changed 1, skipped 1, stopped: unauthorized" s;
        Alcotest.(check bool) "no \"f1\"" false (Text.contains ~sub:"f1" s);
        Alcotest.(check bool) "no \"f2\"" false (Text.contains ~sub:"f2" s) );
  ]
