(* Native checks of app/sync_core/cycle/ (push, pull, schedule, outcome,
   last_error, report) and of synced.ml's local / write: Push.Make and
   Pull.Make run over Cli_local (the sqlite3 CLI) and Sync_fixtures.H
   (Mock_http's identity IO, as test_rest.ml), answered with the recorded
   PostgREST fixtures. *)

module Backoff = Herbier_sync_core.Backoff
module Synced = Herbier_sync_core.Synced
module Outcome = Herbier_sync_core.Cycle.Outcome
module Last_error = Herbier_sync_core.Cycle.Last_error
module Schedule = Herbier_sync_core.Cycle.Schedule
module Push = Herbier_sync_core.Cycle.Push
module Pull = Herbier_sync_core.Cycle.Pull
module Report = Herbier_sync_core.Cycle.Report
module Outbox = Herbier_store.Outbox
module Plants = Herbier_store.Plants
module Tags = Herbier_store.Tags
module References = Herbier_store.References
module Sync_state = Herbier_store.Sync_state
module Ids = Herbier_domain.Ids
module Plant = Herbier_domain.Plant
module Tag = Herbier_domain.Tag
module Observation = Herbier_domain.Observation
module Photo = Herbier_domain.Photo
module Reference = Herbier_domain.Reference
module Fixture = Herbier_test_support.Fixture
module Text = Herbier_test_support.Text
module Cli = Sqlite_cli

(* ---------- Push.Make / Pull.Make, instantiated over the CLI ---------- *)

module H = Sync_fixtures.H
module Push_cli = Push.Make (H) (Cli_local)
module Pull_cli = Pull.Make (H) (Cli_local)

let conn_ok () : (Postgrest.Client.conn, Outcome.stop) result =
  Ok Sync_fixtures.conn

let conn_signed_out () : (Postgrest.Client.conn, Outcome.stop) result =
  Error Outcome.Signed_out

(* ---------- scripted responders ---------- *)

(* One answer per call, in order; fails the test if Push or Pull asks for
   more than were scripted. *)
let sequence responses :
    Mock_http.request -> (Postgrest.Client.response, Mock_http.error) result =
  let remaining = ref responses in
  fun (_ : Mock_http.request) ->
    match !remaining with
    | r :: rest ->
        remaining := rest;
        r
    | [] -> Alcotest.fail "no more scripted responses"

let ok ?(status = 200) body :
    (Postgrest.Client.response, Mock_http.error) result =
  Ok {Postgrest.Client.status; headers = []; body}

(* The table a select/upsert request targets, from its decoded "/rest/v1/<table>"
   target (any query string dropped). *)
let request_table (req : Mock_http.request) =
  let target = Mock_http.decoded_target req.url in
  let path =
    match String.index_opt target '?' with
    | None -> target
    | Some i -> String.sub target 0 i
  in
  match String.length path > 9 with
  | true -> String.sub path 9 (String.length path - 9)
  | false -> path

(* One scripted answer sequence per table, by name; each table's calls are
   answered in the order given for it, independently of the others. *)
let by_table
    (assoc :
      (string * (Postgrest.Client.response, Mock_http.error) result list) list)
    : Mock_http.request -> (Postgrest.Client.response, Mock_http.error) result =
  let queues = List.map (fun (k, v) -> (k, ref v)) assoc in
  fun req ->
    let t = request_table req in
    match List.assoc_opt t queues with
    | None -> Alcotest.failf "no responder scripted for table %s" t
    | Some q -> (
        match !q with
        | r :: rest ->
            q := rest;
            r
        | [] -> Alcotest.failf "table %s: no more scripted responses" t)

(* ---------- result testables ---------- *)

let push_result = Alcotest.testable Push.pp Push.equal
let pull_result = Alcotest.testable Pull.pp Pull.equal

(* ---------- Push ---------- *)

let push_empty_outbox_is_done_no_request () =
  let db = Cli.migrated_db () in
  Mock_http.reset ();
  let conn, calls = Cli_local.counting_conn conn_ok in
  Alcotest.check push_result "empty outbox"
    (Push.Done {pushed = 0; parked = 0})
    (Push_cli.run db ~conn);
  Alcotest.(check int) "no request sent" 0 (List.length !Mock_http.requests);
  Alcotest.(check int) "conn never called" 0 !calls

(* The four edits of Test_push_order.seed, all answered 201: every entry
   pushed, outbox left empty, conn called once per request. *)
let push_all_succeed_empties_the_outbox () =
  let db, _, _ = Test_push_order.seed () in
  Mock_http.reset ();
  Mock_http.respond ~status:201 "";
  let conn, calls = Cli_local.counting_conn conn_ok in
  Alcotest.check push_result "all pushed"
    (Push.Done {pushed = 8; parked = 0})
    (Push_cli.run db ~conn);
  Alcotest.(check int) "outbox empty" 0 (Cli.outbox_count db);
  Alcotest.(check int) "8 requests, conn called once per request" 8 !calls;
  Alcotest.(check (list string))
    "pushed in seq order"
    [
      "plants";
      "observations";
      "photos";
      "tags";
      "plant_tags";
      "plants";
      "photos";
      "observations";
    ]
    (List.map
       (fun (r : Mock_http.request) -> request_table r)
       (List.rev !Mock_http.requests))

let single_entry_db () =
  let db = Cli.migrated_db () in
  let p =
    Sync_fixtures.plant ~at:(Sync_fixtures.time "2026-11-01T09:00:00Z") 1 "Thym"
  in
  let (_ : int) = Cli.edit_ok "one plant" db [Plants.upsert p] in
  db

let push_a_rejected_entry_is_parked () =
  let db = single_entry_db () in
  Mock_http.reset ();
  Mock_http.respond ~status:409
    (Fixture.read "sync_upsert_observations_fk_409.json");
  Alcotest.check push_result "409 parks the entry"
    (Push.Done {pushed = 0; parked = 1})
    (Push_cli.run db ~conn:conn_ok);
  Alcotest.(check int) "the entry is still there" 1 (Cli.outbox_count db);
  match Cli.all db Outbox.parked with
  | [e] ->
      Alcotest.(check (option string))
        "last_error" (Some "HTTP 409") e.last_error;
      Alcotest.(check int) "attempts" 1 e.attempts
  | es -> Alcotest.failf "expected 1 parked entry, got %d" (List.length es)

(* The second of the seed's eight requests answered 409: that entry parks,
   the other seven push. *)
let push_the_second_request_rejected_parks_only_it () =
  let db, _, _ = Test_push_order.seed () in
  Mock_http.reset ();
  let n = ref 0 in
  (Mock_http.responder :=
     fun _ ->
       incr n;
       match !n with
       | 2 ->
           ok ~status:409 (Fixture.read "sync_upsert_observations_fk_409.json")
       | _ -> ok ~status:201 "");
  Alcotest.check push_result "seven pushed, one parked"
    (Push.Done {pushed = 7; parked = 1})
    (Push_cli.run db ~conn:conn_ok);
  Alcotest.(check int) "the parked entry is still there" 1 (Cli.outbox_count db);
  Alcotest.(check int)
    "absent from next" 0
    (List.length (Cli.all db (Outbox.next ~limit:10)));
  match Cli.all db Outbox.parked with
  | [e] ->
      Alcotest.(check string)
        "the observation's entry" "observations" e.table_name;
      Alcotest.(check (option string))
        "last_error" (Some "HTTP 409") e.last_error;
      Alcotest.(check int) "attempts" 1 e.attempts
  | es -> Alcotest.failf "expected 1 parked entry, got %d" (List.length es)

let push_a_400_is_parked () =
  let db = single_entry_db () in
  Mock_http.reset ();
  Mock_http.respond ~status:400
    (Fixture.read "sync_upsert_observations_check_400.json");
  Alcotest.check push_result "400 parks the entry"
    (Push.Done {pushed = 0; parked = 1})
    (Push_cli.run db ~conn:conn_ok);
  match Cli.all db Outbox.parked with
  | [e] ->
      Alcotest.(check (option string))
        "last_error" (Some "HTTP 400") e.last_error
  | es -> Alcotest.failf "expected 1 parked entry, got %d" (List.length es)

(* A raw entry whose table_name is unknown: parked with "invalid entry: …",
   no request ever sent, and later entries still push. *)
let push_an_unknown_table_is_parked_with_no_request () =
  let db = Cli.migrated_db () in
  Cli.exec_ok "a bad entry, then a real plant" db
    (Printf.sprintf
       "insert into outbox (table_name, row_id, op, payload_json, created_at) \
        values ('nope', '%s', 'upsert', '{}', '2026-11-01T09:00:00.000000Z');\n"
       (Sync_fixtures.uuid 1));
  let p =
    Sync_fixtures.plant
      ~at:(Sync_fixtures.time "2026-11-01T09:00:00Z")
      2 "Sauge"
  in
  let (_ : int) = Cli.edit_ok "a real plant after it" db [Plants.upsert p] in
  Mock_http.reset ();
  Mock_http.respond ~status:201 "";
  let conn, calls = Cli_local.counting_conn conn_ok in
  Alcotest.check push_result "the bad entry parks, the plant pushes"
    (Push.Done {pushed = 1; parked = 1})
    (Push_cli.run db ~conn);
  Alcotest.(check int)
    "exactly 1 request (only the real plant)" 1
    (List.length !Mock_http.requests);
  Alcotest.(check int) "conn called for the real plant only" 1 !calls;
  match Cli.all db Outbox.parked with
  | [e] ->
      Alcotest.(check (option string))
        "last_error" (Some "invalid entry: unknown table nope") e.last_error
  | es -> Alcotest.failf "expected 1 parked entry, got %d" (List.length es)

let push_stop_cases () =
  let case name responder expected_stop =
    let db = single_entry_db () in
    Mock_http.reset ();
    Mock_http.responder := responder;
    Alcotest.check push_result name
      (Push.Stopped ({pushed = 0; parked = 0}, expected_stop))
      (Push_cli.run db ~conn:conn_ok);
    Alcotest.(check int)
      (name ^ ": the entry is untouched")
      1 (Cli.outbox_count db);
    match Cli.all db (Outbox.next ~limit:10) with
    | [e] -> Alcotest.(check int) (name ^ ": attempts unchanged") 0 e.attempts
    | es ->
        Alcotest.failf "%s: expected 1 pending entry, got %d" name
          (List.length es)
  in
  case "503: Transient 503" (fun _ -> ok ~status:503 "") (Outcome.Transient 503);
  case "408: Transient 408" (fun _ -> ok ~status:408 "") (Outcome.Transient 408);
  case "429: Transient 429" (fun _ -> ok ~status:429 "") (Outcome.Transient 429);
  case "540: Paused" (fun _ -> ok ~status:540 "") Outcome.Paused;
  case "401 bad jwt: Unauthorized"
    (fun _ ->
      ok ~status:401 (Fixture.read "sync_upsert_plants_bad_jwt_401.json"))
    Outcome.Unauthorized;
  case "offline: Offline \"boom\""
    (fun _ -> Error "boom")
    (Outcome.Offline "boom")

let push_third_request_stops_keeping_the_first_two () =
  let db, _, _ = Test_push_order.seed () in
  Mock_http.reset ();
  Mock_http.responder :=
    sequence [ok ~status:201 ""; ok ~status:201 ""; ok ~status:503 ""];
  Alcotest.check push_result "stops on the third request"
    (Push.Stopped ({pushed = 2; parked = 0}, Outcome.Transient 503))
    (Push_cli.run db ~conn:conn_ok);
  Alcotest.(check int) "entries 3-8 still there" 6 (Cli.outbox_count db);
  let pending = Cli.all db (Outbox.next ~limit:10) in
  Alcotest.(check int) "none parked: all 6 in next" 6 (List.length pending);
  Alcotest.(check bool)
    "attempts 0" true
    (List.for_all (fun (e : Outbox.entry) -> e.attempts = 0) pending);
  Alcotest.(check int)
    "3 requests were sent" 3
    (List.length !Mock_http.requests)

let push_signed_out_sends_no_request () =
  let db = single_entry_db () in
  Mock_http.reset ();
  Alcotest.check push_result "Error Signed_out stops at once"
    (Push.Stopped ({pushed = 0; parked = 0}, Outcome.Signed_out))
    (Push_cli.run db ~conn:conn_signed_out);
  Alcotest.(check int) "no request" 0 (List.length !Mock_http.requests);
  Alcotest.(check int) "outbox unchanged" 1 (Cli.outbox_count db)

(* A plants entry whose payload is no plant row: parked with "invalid entry:
   plants payload: …", no request for it, and the next entry still pushes. *)
let push_an_undecodable_payload_is_parked_with_no_request () =
  let db = Cli.migrated_db () in
  let (_ : int) =
    Cli.write_ok "a plants entry that does not decode" db
      (Outbox.entry_stmt ~table_name:"plants" ~row_id:(Sync_fixtures.uuid 1)
         (`Assoc []))
  in
  let (_ : int) =
    Cli.edit_ok "a real plant after it" db
      [Plants.upsert (Sync_fixtures.plant ~at:Test_push_order.t0 2 "Sauge")]
  in
  Mock_http.reset ();
  Mock_http.respond ~status:201 "";
  let conn, calls = Cli_local.counting_conn conn_ok in
  Alcotest.check push_result "the bad entry parks, the plant pushes"
    (Push.Done {pushed = 1; parked = 1})
    (Push_cli.run db ~conn);
  Alcotest.(check int)
    "exactly 1 request (only the real plant)" 1
    (List.length !Mock_http.requests);
  Alcotest.(check int) "conn called for the real plant only" 1 !calls;
  match Cli.all db Outbox.parked with
  | [e] ->
      Alcotest.(check (option string))
        "last_error" (Some "invalid entry: plants payload: missing column")
        e.last_error
  | es -> Alcotest.failf "expected 1 parked entry, got %d" (List.length es)

let push_stop_is_store stop =
  match stop with
  | Push.Stopped ({pushed = 0; parked = 0}, Outcome.Store _) -> true
  | Push.Stopped _ | Push.Done _ -> false

(* An outbox row that does not decode (op 'delete'): the read fails, the push
   stops on Store with no request. *)
let push_an_unreadable_outbox_stops_on_store () =
  let db = Cli.migrated_db () in
  Cli.exec_ok "an entry whose op is not upsert" db
    (Printf.sprintf
       "insert into outbox (table_name, row_id, op, payload_json, created_at) \
        values ('plants', '%s', 'delete', '{}', '2026-11-01T09:00:00.000000Z');\n"
       (Sync_fixtures.uuid 1));
  Mock_http.reset ();
  let result = Push_cli.run db ~conn:conn_ok in
  Alcotest.(check bool)
    ("Stopped ({0; 0}, Store _): " ^ Push.show result)
    true
    (push_stop_is_store result);
  Alcotest.(check int) "no request" 0 (List.length !Mock_http.requests)

(* The delete after a 201 fails (a trigger refuses it): the push stops on
   Store, the entry still there. *)
let push_a_failed_delete_stops_on_store () =
  let db = single_entry_db () in
  Cli.exec_ok "refuse outbox deletes" db
    "create trigger keep_outbox before delete on outbox begin select \
     raise(abort, 'kept'); end;\n";
  Mock_http.reset ();
  Mock_http.respond ~status:201 "";
  let result = Push_cli.run db ~conn:conn_ok in
  Alcotest.(check bool)
    ("Stopped ({0; 0}, Store _): " ^ Push.show result)
    true
    (push_stop_is_store result);
  Alcotest.(check int) "one request" 1 (List.length !Mock_http.requests);
  Alcotest.(check int) "the entry is still there" 1 (Cli.outbox_count db)

let push_tests =
  let case name f = Alcotest.test_case name `Quick f in
  [
    case
      "a plants entry whose payload does not decode parks as \"invalid entry: \
       plants payload: …\", no request for it"
      push_an_undecodable_payload_is_parked_with_no_request;
    case "an outbox row that does not decode stops on Store, no request"
      push_an_unreadable_outbox_stops_on_store;
    case "a failed delete after a 201 stops on Store"
      push_a_failed_delete_stops_on_store;
    case "empty outbox: Done {0; 0}, 0 requests, conn never called"
      push_empty_outbox_is_done_no_request;
    case
      "the four edits of Test_push_order.seed, all 201: Done {8; 0}, outbox \
       empty, pushed in seq order, conn once per request"
      push_all_succeed_empties_the_outbox;
    case "a rejected (409) entry is parked with last_error \"HTTP 409\""
      push_a_rejected_entry_is_parked;
    case
      "the seed's second request answered 409: Done {7; 1}, that entry parked, \
       absent from next"
      push_the_second_request_rejected_parks_only_it;
    case "a 400 is parked with last_error \"HTTP 400\"" push_a_400_is_parked;
    case
      "an entry of an unknown table parks as \"invalid entry: …\", no request \
       for it; later entries still push"
      push_an_unknown_table_is_parked_with_no_request;
    case "503, 408, 429, 540, 401 and offline each stop without parking"
      push_stop_cases;
    case "the third request's 503 stops, keeping the first two pushed"
      push_third_request_stops_keeping_the_first_two;
    case "conn returning Error Signed_out stops with no request"
      push_signed_out_sends_no_request;
  ]

(* A row shown as its upsert body (Input.to_json, which leaves out an
   unspecified optional field), compared with the table's equal. *)
let row_testable (type table row) (t : (table, row) Synced.t)
    (equal : row -> row -> bool) =
  Alcotest.testable
    (fun f r -> Yojson.Safe.pp f (Postgrest.Input.to_json (Synced.input t r)))
    equal

(* ---------- Synced.id, updated_at, local, write ---------- *)

(* A recorded select answer, decoded as Pull receives it. *)
let decode_fixture (type table row) (t : (table, row) Synced.t) file : row list
    =
  Mock_http.reset ();
  Mock_http.respond ~status:200 (Fixture.read file);
  match
    Sync_fixtures.R.select_since Sync_fixtures.conn t ~since:None ~page:0
  with
  | Ok rows -> rows
  | Error _ -> Alcotest.failf "%s does not decode" file

(* One table: its row equality, and its fixture's id and updated_at, written
   out from the recording. *)
type case =
  | Case : {
      t : ('table, 'row) Synced.t;
      equal : 'row -> 'row -> bool;
      id : int;
      updated_at : string;
    }
      -> case

let cases =
  [
    Case
      {
        t = Synced.plants;
        equal = Plant.equal;
        id = 1;
        updated_at = "2026-11-12T12:25:29.680827Z";
      };
    Case
      {
        t = Synced.tags;
        equal = Tag.equal;
        id = 2;
        updated_at = "2026-11-12T12:25:29.323122Z";
      };
    Case
      {
        t = Synced.observations;
        equal = Observation.equal;
        id = 3;
        updated_at = "2026-11-12T12:25:29.355985Z";
      };
    Case
      {
        t = Synced.photos;
        equal = Photo.equal;
        id = 4;
        updated_at = "2026-11-12T12:25:29.508002Z";
      };
    Case
      {
        t = Synced.plant_tags;
        equal = Tag.Plant_tag.equal;
        id = 5;
        updated_at = "2026-11-12T12:25:29.542462Z";
      };
    Case
      {
        t = Synced.plant_refs;
        equal = Reference.Plant_ref.equal;
        id = 6;
        updated_at = "2026-11-12T12:25:29.615646Z";
      };
    Case
      {
        t = Synced.reference;
        equal = Reference.equal;
        id = 7;
        updated_at = "2026-11-12T12:25:29.652692Z";
      };
  ]

let fixture_of t = Printf.sprintf "sync_select_%s_200.json" (Synced.name t)

let fixture_row (type table row) (t : (table, row) Synced.t) : row =
  match decode_fixture t (fixture_of t) with
  | [row] -> row
  | rows ->
      Alcotest.failf "%s: expected one row, got %d" (fixture_of t)
        (List.length rows)

let count_rows db t =
  Cli.count db
    (Printf.sprintf "select count(*) as n from %s;\n" (Synced.name t))

(* Every case's fixture row written, parents first (cases is in that order). *)
let db_with_every_fixture_row () =
  let db = Cli.migrated_db () in
  List.iter
    (fun (Case {t; _}) ->
      ignore
        (Cli.write_bare_ok (Synced.name t) db (Synced.write t (fixture_row t))
          : int))
    cases;
  db

let synced_id_and_updated_at_of_each_fixture_row () =
  List.iter
    (fun (Case {t; id; updated_at; _}) ->
      let row = fixture_row t in
      let name = Synced.name t in
      Alcotest.(check string)
        (name ^ ": id") (Sync_fixtures.uuid id) (Synced.id t row);
      Alcotest.check Cli.ptime (name ^ ": updated_at")
        (Sync_fixtures.time updated_at)
        (Synced.updated_at t row))
    cases

let synced_write_then_local_gives_the_row () =
  let db = db_with_every_fixture_row () in
  List.iter
    (fun (Case {t; equal; id; _}) ->
      let name = Synced.name t in
      match Cli.all db (Synced.local t [Sync_fixtures.uuid id]) with
      | [got] ->
          Alcotest.check (row_testable t equal)
            (name ^ ": local = the decoded fixture row")
            (fixture_row t) got
      | rows ->
          Alcotest.failf "%s: local gave %d rows, expected 1" name
            (List.length rows))
    cases

let synced_local_of_no_id_or_an_absent_id_is_empty () =
  let db = db_with_every_fixture_row () in
  List.iter
    (fun (Case {t; _}) ->
      let name = Synced.name t in
      Alcotest.(check int)
        (name ^ ": local [] = []") 0
        (List.length (Cli.all db (Synced.local t [])));
      Alcotest.(check int)
        (name ^ ": an absent id = []")
        0
        (List.length (Cli.all db (Synced.local t [Sync_fixtures.uuid 0xff]))))
    cases

let synced_local_returns_a_soft_deleted_row () =
  let db = Cli.migrated_db () in
  match decode_fixture Synced.tags "sync_select_tags_deleted_200.json" with
  | [row] -> (
      ignore
        (Cli.write_bare_ok "the deleted tag" db (Synced.write Synced.tags row)
          : int);
      match Cli.all db (Synced.local Synced.tags [Sync_fixtures.uuid 2]) with
      | [(got : Tag.t)] ->
          Alcotest.check (row_testable Synced.tags Tag.equal) "the row" row got;
          Alcotest.(check bool)
            "deleted_at set" true
            (Option.is_some got.deleted_at)
      | rows -> Alcotest.failf "expected 1 row, got %d" (List.length rows))
  | rows -> Alcotest.failf "expected 1 fixture row, got %d" (List.length rows)

let synced_write_twice_keeps_one_row () =
  let db = db_with_every_fixture_row () in
  List.iter
    (fun (Case {t; _}) ->
      ignore
        (Cli.write_bare_ok (Synced.name t) db (Synced.write t (fixture_row t))
          : int);
      Alcotest.(check int) (Synced.name t ^ ": one row") 1 (count_rows db t))
    cases

(* plant_tags is written on its natural key: a local row of the same (plant,
   tag) under another id is updated in place, its id kept. *)
let synced_write_plant_tag_keeps_the_local_id () =
  let db = Cli.migrated_db () in
  List.iter
    (fun (Case {t; _}) ->
      match Synced.name t with
      | "plants" | "tags" ->
          ignore
            (Cli.write_bare_ok (Synced.name t) db
               (Synced.write t (fixture_row t))
              : int)
      | _ -> ())
    cases;
  let remote = fixture_row Synced.plant_tags in
  let local_id = Sync_fixtures.plant_tag_id 0x55 in
  ignore
    (Cli.write_bare_ok "a local link under another id" db
       (Synced.write Synced.plant_tags {remote with id = local_id})
      : int);
  (match Cli.write_bare db (Synced.write Synced.plant_tags remote) with
  | Ok (_ : int) -> ()
  | Error e -> Alcotest.failf "the remote link: %s" e);
  Alcotest.(check int) "one link" 1 (count_rows db Synced.plant_tags);
  Alcotest.(check int)
    "under the local id" 1
    (List.length
       (Cli.all db (Synced.local Synced.plant_tags [Sync_fixtures.uuid 0x55])))

let synced_tests =
  let case name f = Alcotest.test_case name `Quick f in
  [
    case "id / updated_at of each fixture row are the recording's"
      synced_id_and_updated_at_of_each_fixture_row;
    case "write of each fixture row, then local [id] = that row"
      synced_write_then_local_gives_the_row;
    case "local [] and local [absent id] are []"
      synced_local_of_no_id_or_an_absent_id_is_empty;
    case "local returns a soft-deleted row"
      synced_local_returns_a_soft_deleted_row;
    case "write twice keeps one row" synced_write_twice_keeps_one_row;
    case "plant_tags: the same (plant, tag) under another id keeps the local id"
      synced_write_plant_tag_keeps_the_local_id;
  ]

(* ---------- Pull ---------- *)

let synced_names = List.map (fun (Synced.Any t) -> Synced.name t) Synced.all

let fresh_pull_fixture_tables =
  List.map (fun (Synced.Any t) -> (Synced.name t, fixture_of t)) Synced.all

let responder_of_fixtures tables =
  by_table
    (List.map
       (fun (table, file) -> (table, [ok ~status:200 (Fixture.read file)]))
       tables)

(* The tables of [fixtures] answered their fixture, the others []. *)
let with_fixtures fixtures =
  by_table
    (List.map
       (fun name ->
         ( name,
           [
             ok
               (match List.assoc_opt name fixtures with
               | Some file -> Fixture.read file
               | None -> "[]");
           ] ))
       synced_names)

(* The other six tables answered [] (one request each). *)
let only table answers =
  by_table
    ((table, answers)
    :: List.filter_map
         (fun (Synced.Any t) ->
           match String.equal (Synced.name t) table with
           | true -> None
           | false -> Some (Synced.name t, [ok ~status:200 "[]"]))
         Synced.all)

let pull_fresh_db_all_tables_inserted_once () =
  let db = Cli.migrated_db () in
  Mock_http.reset ();
  Mock_http.responder := responder_of_fixtures fresh_pull_fixture_tables;
  match Pull_cli.run db ~conn:conn_ok with
  | Pull.Done reports ->
      List.iter
        (fun (r : Pull.table_report) ->
          Alcotest.(check int) (r.table ^ ": inserted = 1") 1 r.inserted;
          Alcotest.(check int) (r.table ^ ": replaced = 0") 0 r.replaced)
        reports;
      Alcotest.(check int) "Pull.writes = 7" 7 (Pull.writes reports);
      let requests = List.rev !Mock_http.requests in
      Alcotest.(check (list string))
        "7 GETs in Synced.all order" synced_names
        (List.map request_table requests);
      List.iter
        (fun (r : Mock_http.request) ->
          let table = request_table r in
          Alcotest.(check bool)
            (table ^ ": no updated_at filter")
            false
            (Text.contains ~sub:"updated_at=gt"
               (Mock_http.decoded_target r.url));
          Alcotest.(check (option string))
            (table ^ ": Range 0-499") (Some "0-499")
            (Mock_http.header "Range" r))
        requests;
      List.iter
        (fun (Case {t; equal; id; _}) ->
          match Cli.all db (Synced.local t [Sync_fixtures.uuid id]) with
          | [got] ->
              Alcotest.check (row_testable t equal)
                (Synced.name t ^ ": the stored row is the fixture's")
                (fixture_row t) got
          | rows ->
              Alcotest.failf "%s: %d rows stored" (Synced.name t)
                (List.length rows))
        cases;
      Alcotest.(check int) "no outbox entry" 0 (Cli.outbox_count db)
  | Pull.Stopped s ->
      Alcotest.failf "expected Done, got Stopped %s" (Outcome.to_string s)

let pull_cursors_after_fresh_pull () =
  let db = Cli.migrated_db () in
  Mock_http.reset ();
  Mock_http.responder := responder_of_fixtures fresh_pull_fixture_tables;
  (match Pull_cli.run db ~conn:conn_ok with
  | Pull.Done _ -> ()
  | Pull.Stopped s ->
      Alcotest.failf "expected Done, got %s" (Outcome.to_string s));
  let by_name = List.sort (fun (a, _) (b, _) -> String.compare a b) in
  Alcotest.(check (list (pair string Cli.ptime)))
    "every table's cursor is the fixture's updated_at"
    (by_name
       (List.map
          (fun (Case {t; updated_at; _}) ->
            (Synced.name t, Sync_fixtures.time updated_at))
          cases))
    (by_name (Cli.all db Sync_state.all))

(* Same answers again, over a db already at those cursors: every table
   unchanged (the reference payload compared structurally, whatever its key
   order), no write, Pull.writes = 0; each request filtered on its cursor. *)
let pull_same_answers_again_are_unchanged () =
  let db = Cli.migrated_db () in
  Mock_http.reset ();
  Mock_http.responder := responder_of_fixtures fresh_pull_fixture_tables;
  (match Pull_cli.run db ~conn:conn_ok with
  | Pull.Done _ -> ()
  | Pull.Stopped s ->
      Alcotest.failf "first pull: expected Done, got %s" (Outcome.to_string s));
  Mock_http.reset ();
  Mock_http.responder := responder_of_fixtures fresh_pull_fixture_tables;
  match Pull_cli.run db ~conn:conn_ok with
  | Pull.Done reports ->
      List.iter
        (fun (r : Pull.table_report) ->
          Alcotest.(check int) (r.table ^ ": unchanged = 1") 1 r.unchanged;
          Alcotest.(check int) (r.table ^ ": inserted = 0") 0 r.inserted;
          Alcotest.(check int) (r.table ^ ": replaced = 0") 0 r.replaced)
        reports;
      Alcotest.(check int) "Pull.writes = 0" 0 (Pull.writes reports);
      (* Every fixture's updated_at is 2026-11-12T12:25:29.xxxxxxZ: minus
         5 s, in whole seconds. *)
      List.iter
        (fun (r : Mock_http.request) ->
          Alcotest.(check bool)
            (request_table r ^ ": updated_at=gt.<cursor - 5 s>")
            true
            (Text.contains ~sub:"updated_at=gt.2026-11-12T12:25:24Z"
               (Mock_http.decoded_target r.url)))
        !Mock_http.requests;
      Alcotest.(check int) "7 requests" 7 (List.length !Mock_http.requests)
  | Pull.Stopped s ->
      Alcotest.failf "second pull: expected Done, got %s" (Outcome.to_string s)

let seed_pull db =
  Mock_http.reset ();
  Mock_http.responder := responder_of_fixtures fresh_pull_fixture_tables;
  match Pull_cli.run db ~conn:conn_ok with
  | Pull.Done _ -> ()
  | Pull.Stopped s ->
      Alcotest.failf "seed pull: expected Done, got %s" (Outcome.to_string s)

(* The fixture plant renamed locally, with a later local updated_at. *)
let renamed_plant : Plant.t =
  {
    id = Sync_fixtures.plant_id 1;
    display_name = "Digitale (renommée)";
    aliases = ["Digitale"; "Gant de Notre-Dame"];
    scientific_name = Some "Digitalis purpurea";
    authorship = Some "L.";
    gbif_key = Some 5414995;
    notes = "Mi-ombre";
    notes_updated_at = Some (Sync_fixtures.time "2026-11-12T09:07:00Z");
    cover_photo_id = Some (Sync_fixtures.photo_id 4);
    created_at = Sync_fixtures.time "2026-11-12T09:00:00Z";
    updated_at = Sync_fixtures.time "2026-11-13T08:00:00Z";
    deleted_at = None;
  }

let table_report table = function
  | Pull.Done reports -> (
      match
        List.find_opt
          (fun (r : Pull.table_report) -> String.equal r.table table)
          reports
      with
      | Some r -> r
      | None -> Alcotest.failf "no %s report" table)
  | Pull.Stopped s ->
      Alcotest.failf "expected Done, got Stopped %s" (Outcome.to_string s)

let plants_report = table_report "plants"
let plant_row = row_testable Synced.plants Plant.equal

let local_plant db =
  match Cli.all db (Synced.local Synced.plants [Sync_fixtures.uuid 1]) with
  | [p] -> p
  | ps -> Alcotest.failf "%d local plants, expected 1" (List.length ps)

let pull_plants_again db =
  Mock_http.reset ();
  Mock_http.responder :=
    only "plants" [ok (Fixture.read "sync_select_plants_200.json")];
  plants_report (Pull_cli.run db ~conn:conn_ok)

(* A local edit to the plant, with its pending outbox entry: the pull keeps
   the local row ([Keep_local]), the entry stays, the cursor still moves. *)
let pull_keeps_a_locally_edited_pending_row () =
  let db = Cli.migrated_db () in
  seed_pull db;
  let (_ : int) =
    Cli.edit_ok "a local rename, pending push" db [Plants.upsert renamed_plant]
  in
  (* Cleared, so that only this pull can set the plants cursor. *)
  let (_ : int) = Cli.write_ok "reset cursors" db Sync_state.reset in
  let r = pull_plants_again db in
  Alcotest.(check int) "kept_local = 1" 1 r.kept_local;
  Alcotest.(check int) "replaced = 0" 0 r.replaced;
  Alcotest.(check (option Cli.ptime))
    "the stored plants cursor still moved"
    (Some (Sync_fixtures.time "2026-11-12T12:25:29.680827Z"))
    (List.assoc_opt "plants" (Cli.all db Sync_state.all));
  Alcotest.check plant_row "the local row is unchanged" renamed_plant
    (local_plant db);
  Alcotest.(check int) "the entry is still there" 1 (Cli.outbox_count db)

(* The same edit, its entry parked: it no longer protects the row. *)
let pull_replaces_a_row_whose_only_entry_is_parked () =
  let db = Cli.migrated_db () in
  seed_pull db;
  let (_ : int) =
    Cli.edit_ok "a local rename" db [Plants.upsert renamed_plant]
  in
  (match Cli.all db (Outbox.next ~limit:10) with
  | [e] ->
      ignore
        (Cli.write_ok "park it" db (Outbox.park e.seq ~error:"HTTP 400") : int)
  | es -> Alcotest.failf "%d entries, expected 1" (List.length es));
  let r = pull_plants_again db in
  Alcotest.(check int) "replaced = 1" 1 r.replaced;
  Alcotest.check plant_row "the local row is the remote one"
    (fixture_row Synced.plants)
    (local_plant db);
  Alcotest.(check int) "the parked entry is kept" 1 (Cli.outbox_count db)

(* A differing local row with a later local updated_at and no entry: the
   server's order wins (the device clock may be skewed). *)
let pull_replaces_a_later_local_row_without_an_entry () =
  let db = Cli.migrated_db () in
  seed_pull db;
  ignore
    (Cli.write_bare_ok "a later local row, no entry" db
       (Synced.write Synced.plants renamed_plant)
      : int);
  let r = pull_plants_again db in
  Alcotest.(check int) "replaced = 1" 1 r.replaced;
  Alcotest.check plant_row "the local row is the remote one"
    (fixture_row Synced.plants)
    (local_plant db)

let third_table_name = "observations"

let pull_transient_on_a_table_stops_with_nothing_written () =
  let db = Cli.migrated_db () in
  Mock_http.reset ();
  Mock_http.responder :=
    by_table
      [
        ("plants", [ok ~status:200 (Fixture.read "sync_select_plants_200.json")]);
        ("tags", [ok ~status:200 (Fixture.read "sync_select_tags_200.json")]);
        (third_table_name, [ok ~status:503 ""]);
      ];
  (match Pull_cli.run db ~conn:conn_ok with
  | Pull.Stopped (Outcome.Transient 503) -> ()
  | Pull.Stopped s ->
      Alcotest.failf "expected Transient 503, got %s" (Outcome.to_string s)
  | Pull.Done _ -> Alcotest.fail "expected Stopped");
  Alcotest.(check (list string))
    "no cursor was written" []
    (List.map fst (Cli.all db Sync_state.all));
  Alcotest.(check int)
    "no plant written, though plants was fetched" 0
    (Cli.count db "select count(*) as n from plants;\n");
  Alcotest.(check int)
    "no tag written, though tags was fetched" 0
    (Cli.count db "select count(*) as n from tags;\n")

(* A cursor that does not decode: the pull stops on Store before any
   request. *)
let pull_an_unreadable_cursor_stops_on_store () =
  let db = Cli.migrated_db () in
  Cli.exec_ok "a cursor that is no date" db
    "insert into sync_state (table_name, last_pulled_at) values ('plants', \
     'not a date');\n";
  Mock_http.reset ();
  (match Pull_cli.run db ~conn:conn_ok with
  | Pull.Stopped (Outcome.Store _) -> ()
  | Pull.Stopped s ->
      Alcotest.failf "expected Store _, got %s" (Outcome.to_string s)
  | Pull.Done _ -> Alcotest.fail "expected Stopped");
  Alcotest.(check int) "no request" 0 (List.length !Mock_http.requests)

(* A stop on the first table: nothing written, no cursor. *)
let pull_stop_cases () =
  let case name answer expected =
    let db = Cli.migrated_db () in
    Mock_http.reset ();
    Mock_http.responder := only "plants" [answer];
    Alcotest.check pull_result name (Pull.Stopped expected)
      (Pull_cli.run db ~conn:conn_ok);
    Alcotest.(check int)
      (name ^ ": one request") 1
      (List.length !Mock_http.requests);
    Alcotest.(check (list string))
      (name ^ ": no cursor") []
      (List.map fst (Cli.all db Sync_state.all))
  in
  case "540: Paused" (ok ~status:540 "") Outcome.Paused;
  case "401: Unauthorized"
    (ok ~status:401 (Fixture.read "sync_upsert_plants_bad_jwt_401.json"))
    Outcome.Unauthorized;
  case "404: Rejected 404" (ok ~status:404 "") (Outcome.Rejected 404);
  case "offline: Offline \"boom\"" (Error "boom") (Outcome.Offline "boom")

let pull_a_non_array_body_is_bad_response () =
  let db = Cli.migrated_db () in
  Mock_http.reset ();
  Mock_http.responder :=
    by_table
      [
        ("plants", [ok ~status:200 "{}"]);
        ("tags", [ok ~status:200 "[]"]);
        ("observations", [ok ~status:200 "[]"]);
        ("photos", [ok ~status:200 "[]"]);
        ("plant_tags", [ok ~status:200 "[]"]);
        ("plant_refs", [ok ~status:200 "[]"]);
        ("reference", [ok ~status:200 "[]"]);
      ];
  match Pull_cli.run db ~conn:conn_ok with
  | Pull.Stopped (Outcome.Bad_response _) -> ()
  | Pull.Stopped s ->
      Alcotest.failf "expected Bad_response, got %s" (Outcome.to_string s)
  | Pull.Done _ -> Alcotest.fail "expected Stopped"

let pull_signed_out_sends_no_request () =
  let db = Cli.migrated_db () in
  Mock_http.reset ();
  Alcotest.check pull_result "Error Signed_out"
    (Pull.Stopped Outcome.Signed_out)
    (Pull_cli.run db ~conn:conn_signed_out);
  Alcotest.(check int) "no request" 0 (List.length !Mock_http.requests)

(* An observation referencing a plant the server has not sent yet (a fresh
   db, plants answered empty): the transaction's deferred foreign key fails
   at commit, nothing is written anywhere, no cursor moved. A second pull
   with the plant this time succeeds. *)
let pull_orphan_child_rolls_back_the_whole_transaction () =
  let db = Cli.migrated_db () in
  Mock_http.reset ();
  Mock_http.responder :=
    with_fixtures [("observations", "sync_select_observations_200.json")];
  (match Pull_cli.run db ~conn:conn_ok with
  | Pull.Stopped (Outcome.Store _) -> ()
  | Pull.Stopped s ->
      Alcotest.failf "expected Store _, got %s" (Outcome.to_string s)
  | Pull.Done _ -> Alcotest.fail "expected Stopped (the orphan foreign key)");
  Alcotest.(check (list string))
    "no cursor at all" []
    (List.map fst (Cli.all db Sync_state.all));
  List.iter
    (fun (Synced.Any t) ->
      Alcotest.(check int)
        (Synced.name t ^ ": no row")
        0
        (Cli.count db
           (Printf.sprintf "select count(*) as n from %s;\n" (Synced.name t))))
    Synced.all;
  Mock_http.reset ();
  Mock_http.responder :=
    with_fixtures
      [
        ("plants", "sync_select_plants_200.json");
        ("observations", "sync_select_observations_200.json");
      ];
  match Pull_cli.run db ~conn:conn_ok with
  | Pull.Done _ ->
      Alcotest.(check int)
        "both rows now present" 1
        (Cli.count db "select count(*) as n from plants;\n");
      Alcotest.(check int)
        "the observation too" 1
        (Cli.count db "select count(*) as n from observations;\n")
  | Pull.Stopped s ->
      Alcotest.failf "expected Done, got %s" (Outcome.to_string s)

let tags_report = table_report "tags"

let tag_ranges () =
  List.filter_map
    (fun (r : Mock_http.request) ->
      match String.equal (request_table r) "tags" with
      | true -> Some (Option.value (Mock_http.header "Range" r) ~default:"-")
      | false -> None)
    (List.rev !Mock_http.requests)

(* page0: the deleted fixture tag and Tag 001 … Tag 499; page1: Tag 500. *)
let pull_paging_stops_on_a_short_page () =
  let db = Cli.migrated_db () in
  Mock_http.reset ();
  Mock_http.responder :=
    only "tags"
      [
        ok (Fixture.read "sync_select_tags_page0_200.json");
        ok (Fixture.read "sync_select_tags_page1_200.json");
      ];
  let r = tags_report (Pull_cli.run db ~conn:conn_ok) in
  Alcotest.(check (list string))
    "pages 0-499 then 500-999, then stop" ["0-499"; "500-999"] (tag_ranges ());
  Alcotest.(check int) "501 tags inserted" 501 r.inserted;
  Alcotest.(check int)
    "501 tag rows stored" 501
    (Cli.count db "select count(*) as n from tags;\n");
  Alcotest.(check (option Cli.ptime))
    "cursor = the greatest updated_at (page 1's Tag 500)"
    (Some (Sync_fixtures.time "2026-11-12T14:19:31.148718Z"))
    r.cursor;
  (* The same pages over the stored rows: every row is found locally, across
     both chunks of ids (500, then 1). *)
  let (_ : int) = Cli.write_ok "reset cursors" db Sync_state.reset in
  Mock_http.reset ();
  Mock_http.responder :=
    only "tags"
      [
        ok (Fixture.read "sync_select_tags_page0_200.json");
        ok (Fixture.read "sync_select_tags_page1_200.json");
      ];
  let r = tags_report (Pull_cli.run db ~conn:conn_ok) in
  Alcotest.(check int) "again: 501 unchanged" 501 r.unchanged;
  Alcotest.(check int) "again: none inserted" 0 r.inserted;
  Alcotest.(check int) "again: none replaced" 0 r.replaced

(* Two rows, the later updated_at first: the cursor is the greatest, not the
   last row's. *)
let pull_cursor_is_the_greatest_updated_at_not_the_last () =
  let db = Cli.migrated_db () in
  let later = Sync_fixtures.time "2026-11-12T10:00:00Z" in
  let earlier = Sync_fixtures.time "2026-11-12T09:00:00Z" in
  let row tag = Postgrest.Input.to_json (Synced.input Synced.tags tag) in
  Mock_http.reset ();
  Mock_http.responder :=
    only "tags"
      [
        ok
          (Yojson.Safe.to_string
             (`List
                [
                  row (Sync_fixtures.tag ~at:later 1 "B");
                  row (Sync_fixtures.tag ~at:earlier 2 "A");
                ]));
      ];
  let r = tags_report (Pull_cli.run db ~conn:conn_ok) in
  Alcotest.(check (option Cli.ptime)) "cursor" (Some later) r.cursor

let pull_a_full_page_then_an_empty_one_stops () =
  let db = Cli.migrated_db () in
  Mock_http.reset ();
  Mock_http.responder :=
    only "tags"
      [
        ok (Fixture.read "sync_select_tags_page0_200.json");
        ok (Fixture.read "sync_select_plants_empty_200.json");
      ];
  let r = tags_report (Pull_cli.run db ~conn:conn_ok) in
  Alcotest.(check (list string))
    "two requests, the second answered []" ["0-499"; "500-999"] (tag_ranges ());
  Alcotest.(check int) "500 tags inserted" 500 r.inserted

(* The offset race (architecture §4): Tag 001 written again between the two
   page requests comes back on page 1, pushing Tag 500 back out of reach.
   Kept once, as its newer version ("Tag 001 bis"); Tag 500 is missed, which
   is why the tags cursor stays absent (the next pull reads the window
   again); the others are written. *)
let pull_a_repeated_id_across_pages_keeps_the_newer_and_skips_the_cursor () =
  let db = Cli.migrated_db () in
  Mock_http.reset ();
  Mock_http.responder :=
    by_table
      (List.map
         (fun (table, file) ->
           match String.equal table "tags" with
           | true ->
               ( table,
                 [
                   ok (Fixture.read "sync_select_tags_page0_200.json");
                   ok (Fixture.read "sync_select_tags_page1_moved_200.json");
                 ] )
           | false -> (table, [ok (Fixture.read file)]))
         fresh_pull_fixture_tables);
  let r = tags_report (Pull_cli.run db ~conn:conn_ok) in
  let tag_001 = Sync_fixtures.uuid 0x1001 in
  Alcotest.(check bool) "repeated" true r.repeated;
  Alcotest.(check (option Cli.ptime))
    "no tags cursor in the report" None r.cursor;
  Alcotest.(check int)
    "Tag 001 stored once" 1
    (Cli.count db
       (Printf.sprintf "select count(*) as n from tags where id = '%s';\n"
          tag_001));
  Alcotest.(check int)
    "Tag 001 with its newer name" 1
    (Cli.count db
       (Printf.sprintf
          "select count(*) as n from tags where id = '%s' and name = 'Tag 001 \
           bis';\n"
          tag_001));
  Alcotest.(check int)
    "500 tags: Tag 500 missed, Tag 001 not duplicated" 500
    (Cli.count db "select count(*) as n from tags;\n");
  Alcotest.(check (list string))
    "every cursor but tags'"
    [
      "observations"; "photos"; "plant_refs"; "plant_tags"; "plants"; "reference";
    ]
    (List.map fst (Cli.all db Sync_state.all))

(* The fixture tag live locally, then the server's soft-deleted version. *)
let pull_a_soft_deleted_row_replaces_the_live_one () =
  let db = Cli.migrated_db () in
  Mock_http.reset ();
  Mock_http.responder :=
    only "tags" [ok (Fixture.read "sync_select_tags_200.json")];
  let (_ : Pull.t) = Pull_cli.run db ~conn:conn_ok in
  Alcotest.(check int) "the tag is live" 1 (List.length (Cli.all db Tags.list));
  Mock_http.reset ();
  Mock_http.responder :=
    only "tags" [ok (Fixture.read "sync_select_tags_deleted_200.json")];
  let r = tags_report (Pull_cli.run db ~conn:conn_ok) in
  Alcotest.(check int) "replaced = 1" 1 r.replaced;
  Alcotest.(check int)
    "Tags.list no longer has it" 0
    (List.length (Cli.all db Tags.list))

(* ---------- Push from A, pull into B ---------- *)

let without_updated_at = function
  | `Assoc fields ->
      `Assoc
        (List.filter (fun (k, _) -> not (String.equal k "updated_at")) fields)
  | j -> j

let with_updated_at at = function
  | `Assoc fields ->
      `Assoc
        (List.map
           (function "updated_at", _ -> ("updated_at", `String at) | f -> f)
           fields)
  | j -> j

(* Every upsert body A's push sent, by table, the last per id (what the
   server holds), with updated_at set as the server's trigger would. *)
let server_rows requests =
  List.fold_left
    (fun acc (r : Mock_http.request) ->
      let body = Test_push_order.body_of r in
      let id = Test_push_order.string_field "id" body in
      let table = request_table r in
      let rows = Option.value (List.assoc_opt table acc) ~default:[] in
      let rows =
        List.filter
          (fun row ->
            not (String.equal (Test_push_order.string_field "id" row) id))
          rows
        @ [with_updated_at "2026-11-12T15:00:00.123456+00:00" body]
      in
      (table, rows) :: List.remove_assoc table acc)
    [] requests

(* A's local rows of a table, by the ids the server holds, as their upsert
   bodies without updated_at (the server's, not A's), sorted by id. *)
let rows_json db (Synced.Any t) ids =
  List.sort compare
    (List.map
       (fun row ->
         Yojson.Safe.to_string
           (without_updated_at (Postgrest.Input.to_json (Synced.input t row))))
       (Cli.all db (Synced.local t ids)))

let push_from_a_then_pull_into_b_gives_a_s_rows () =
  let a, p, _ = Test_push_order.seed () in
  let at = Sync_fixtures.time "2026-11-01T09:05:00Z" in
  let (_ : int) =
    Cli.edit_ok "a reference and a plant ref" a
      [
        References.put ~plant:p.id ~source:Reference.Source.Gbif ~fetched_at:at
          ~payload:
            (`Assoc
               [
                 ("key", `Int 5414995);
                 ("names", `List [`String "Thym"; `String "Farigoule"]);
                 ("rank", `Assoc [("z", `Bool true); ("a", `Null)]);
               ])
          ~status:Reference.Status.Complete ~at;
        References.link ~plant:p.id ~source:Reference.Source.Gbif
          ~external_id:"5414995" ~url:"https://www.gbif.org/species/5414995" ~at;
      ]
  in
  Mock_http.reset ();
  Mock_http.respond ~status:201 "";
  Alcotest.check push_result "A pushes all ten"
    (Push.Done {pushed = 10; parked = 0})
    (Push_cli.run a ~conn:conn_ok);
  let server = server_rows (List.rev !Mock_http.requests) in
  let b = Cli.migrated_db () in
  Mock_http.reset ();
  Mock_http.responder :=
    by_table
      (List.map
         (fun (Synced.Any t) ->
           let rows =
             Option.value (List.assoc_opt (Synced.name t) server) ~default:[]
           in
           (Synced.name t, [ok (Yojson.Safe.to_string (`List rows))]))
         Synced.all);
  (match Pull_cli.run b ~conn:conn_ok with
  | Pull.Done _ -> ()
  | Pull.Stopped s ->
      Alcotest.failf "B's pull: expected Done, got %s" (Outcome.to_string s));
  List.iter
    (fun (Synced.Any t as any) ->
      let name = Synced.name t in
      let ids =
        List.map
          (Test_push_order.string_field "id")
          (Option.value (List.assoc_opt name server) ~default:[])
      in
      Alcotest.(check bool) (name ^ ": pushed at least one row") true (ids <> []);
      Alcotest.(check (list string))
        (name ^ ": B's rows are A's")
        (rows_json a any ids) (rows_json b any ids))
    Synced.all;
  Alcotest.(check int) "B has no outbox entry" 0 (Cli.outbox_count b)

let pull_tests =
  let case name f = Alcotest.test_case name `Quick f in
  [
    case
      "fresh db, all seven fixtures: Done, each inserted = 1, 7 GETs in order \
       with no filter and Range 0-499, rows stored, no outbox entry"
      pull_fresh_db_all_tables_inserted_once;
    case "after a fresh pull, every cursor is the fixture's updated_at"
      pull_cursors_after_fresh_pull;
    case
      "the same answers again: every table unchanged, Pull.writes = 0, \
       filtered on cursor - 5 s"
      pull_same_answers_again_are_unchanged;
    case
      "a locally edited, pending plant is kept (Keep_local), entry kept, \
       cursor still moves"
      pull_keeps_a_locally_edited_pending_row;
    case "a row whose only entry is parked is replaced, the entry kept"
      pull_replaces_a_row_whose_only_entry_is_parked;
    case "a later local row with no entry is replaced (server order wins)"
      pull_replaces_a_later_local_row_without_an_entry;
    case "a soft-deleted remote row replaces the live local one"
      pull_a_soft_deleted_row_replaces_the_live_one;
    case "503 on a table stops the pull, nothing written anywhere, no cursor"
      pull_transient_on_a_table_stops_with_nothing_written;
    case "540, 401, another 4xx and offline each stop, nothing written"
      pull_stop_cases;
    case "a non-array 200 body is Bad_response"
      pull_a_non_array_body_is_bad_response;
    case "conn returning Error Signed_out sends no request"
      pull_signed_out_sends_no_request;
    case
      "an orphan child (its parent not yet pulled) rolls back the whole \
       transaction; a later pull with the parent succeeds"
      pull_orphan_child_rolls_back_the_whole_transaction;
    case
      "paging: 0-499 then 500-999, stops on the short page, cursor the \
       greatest updated_at"
      pull_paging_stops_on_a_short_page;
    case "the cursor is the greatest updated_at, not the last row's"
      pull_cursor_is_the_greatest_updated_at_not_the_last;
    case "a full page then an empty one stops after the empty one"
      pull_a_full_page_then_an_empty_one_stops;
    case
      "a repeated id across two pages is kept once (the newer version), its \
       table's cursor is not written, the others are"
      pull_a_repeated_id_across_pages_keeps_the_newer_and_skips_the_cursor;
    case "a cursor that does not decode stops on Store, no request"
      pull_an_unreadable_cursor_stops_on_store;
    case
      "push from db A, its bodies answered to the pull of db B: B holds A's \
       rows, updated_at aside, in every table"
      push_from_a_then_pull_into_b_gives_a_s_rows;
  ]

(* ---------- Schedule ---------- *)

let state = Alcotest.testable Schedule.pp_state Schedule.equal_state
let action = Alcotest.testable Schedule.pp_action Schedule.equal_action

let check_trigger what st trig expected_st expected_act =
  let st', act = Schedule.trigger st trig in
  Alcotest.check state (what ^ ": state") expected_st st';
  Alcotest.check action (what ^ ": action") expected_act act

let check_finished what st stop expected_st expected_act =
  let st', act = Schedule.finished st stop in
  Alcotest.check state (what ^ ": state") expected_st st';
  Alcotest.check action (what ^ ": action") expected_act act

let idle0 = Schedule.Idle {attempt = 0}
let running0 = Schedule.Running {attempt = 0; again = None; background = false}

let running0_again t =
  Schedule.Running {attempt = 0; again = Some t; background = false}

let running0_bg =
  Schedule.Running {attempt = 0; again = None; background = true}

let schedule_trigger_table () =
  check_trigger "Idle + Retry_timer" idle0 Schedule.Retry_timer idle0
    Schedule.Nothing;
  check_trigger "Idle + Backgrounded" idle0 Schedule.Backgrounded idle0
    Schedule.Nothing;
  List.iter
    (fun t -> check_trigger "Idle + other" idle0 t running0 (Schedule.Run t))
    [Schedule.Start; Resume; Local_write; Signed_in; Manual];
  check_trigger "Running + Backgrounded" running0 Schedule.Backgrounded
    running0_bg Schedule.Nothing;
  check_trigger "Running (background) + Backgrounded" running0_bg
    Schedule.Backgrounded running0_bg Schedule.Nothing;
  check_trigger "Running + Retry_timer" running0 Schedule.Retry_timer running0
    Schedule.Nothing;
  List.iter
    (fun t ->
      check_trigger "Running + other" running0 t (running0_again t)
        Schedule.Nothing;
      check_trigger "Running (background) + other clears background" running0_bg
        t (running0_again t) Schedule.Nothing;
      check_trigger "Running (again) + other keeps the latest"
        (running0_again Schedule.Manual)
        t (running0_again t) Schedule.Nothing)
    [Schedule.Start; Resume; Local_write; Signed_in; Manual];
  let waiting2 = Schedule.Waiting {attempt = 2} in
  check_trigger "Waiting + Backgrounded" waiting2 Schedule.Backgrounded
    (Schedule.Idle {attempt = 2})
    Schedule.Cancel_timer;
  List.iter
    (fun t ->
      check_trigger "Waiting + other" waiting2 t
        (Schedule.Running {attempt = 2; again = None; background = false})
        (Schedule.Run t))
    [Schedule.Start; Resume; Local_write; Signed_in; Manual; Retry_timer]

let schedule_finished_table () =
  check_finished "Idle + anything is unchanged" idle0 None idle0
    Schedule.Nothing;
  check_finished "Waiting + anything is unchanged"
    (Schedule.Waiting {attempt = 1})
    None
    (Schedule.Waiting {attempt = 1})
    Schedule.Nothing;
  check_finished "Running (again) + completed: Run with the queued trigger"
    (running0_again Schedule.Local_write)
    None running0 (Schedule.Run Schedule.Local_write);
  check_finished "Running (not again) + completed" running0 None idle0
    Schedule.Nothing;
  check_finished "Running + Signed_out: Idle {0}, Nothing, again dropped"
    (Schedule.Running {attempt = 3; again = Some Manual; background = false})
    (Some Outcome.Signed_out) idle0 Schedule.Nothing;
  check_finished "Running (again) + a retried stop: Running, Run"
    (running0_again Schedule.Resume)
    (Some (Outcome.Offline "x"))
    (Schedule.Running {attempt = 1; again = None; background = false})
    (Schedule.Run Schedule.Resume);
  check_finished
    "Running (not again) + a retried stop: Waiting, Wait (retry_delay 1)"
    running0 (Some (Outcome.Offline "x"))
    (Schedule.Waiting {attempt = 1})
    (Schedule.Wait (Backoff.delay ~attempt:1));
  check_finished "Running (background) + a retried stop: Idle, no timer"
    (Schedule.Running {attempt = 2; again = None; background = true})
    (Some (Outcome.Offline "x"))
    (Schedule.Idle {attempt = 3})
    Schedule.Nothing;
  check_finished
    "Running (background, again) + a retried stop: Idle, no timer, again \
     dropped"
    (Schedule.Running {attempt = 2; again = Some Manual; background = true})
    (Some (Outcome.Offline "x"))
    (Schedule.Idle {attempt = 3})
    Schedule.Nothing;
  check_finished "Running (background, again) + completed: the rerun keeps it"
    (Schedule.Running {attempt = 0; again = Some Manual; background = true})
    None running0_bg (Schedule.Run Manual)

(* Backgrounded while a cycle runs, which then stops on a retried outcome: no
   retry timer is armed in the background; Resume runs at once, attempt
   kept. *)
let schedule_backgrounded_during_a_failing_cycle_arms_no_timer () =
  let st, act = Schedule.trigger idle0 Schedule.Local_write in
  Alcotest.check action "Run" (Schedule.Run Local_write) act;
  let st, act = Schedule.trigger st Schedule.Backgrounded in
  Alcotest.check action "Nothing while running" Schedule.Nothing act;
  let st, act = Schedule.finished st (Some (Outcome.Offline "x")) in
  Alcotest.check state "Idle, attempt counted" (Schedule.Idle {attempt = 1}) st;
  Alcotest.check action "no Wait" Schedule.Nothing act;
  let st, act = Schedule.trigger st Schedule.Resume in
  Alcotest.check action "Resume runs" (Schedule.Run Resume) act;
  Alcotest.check state "attempt kept, foreground"
    (Schedule.Running {attempt = 1; again = None; background = false})
    st

let schedule_local_write_during_a_cycle_runs_once_more () =
  let st, act = Schedule.trigger running0 Schedule.Local_write in
  Alcotest.check state "Running, again" (running0_again Local_write) st;
  Alcotest.check action "no Run while running" Schedule.Nothing act;
  let st, act = Schedule.finished st None in
  Alcotest.check state "the queued run starts" running0 st;
  Alcotest.check action "Run, as the local write" (Schedule.Run Local_write) act;
  let st, act = Schedule.finished st None in
  Alcotest.check state "back to idle" idle0 st;
  Alcotest.check action "Nothing" Schedule.Nothing act

let schedule_six_failures_back_off_then_cap_then_reset () =
  let delays = [10; 20; 40; 80; 160; 300; 300] in
  let (_ : Schedule.state) =
    List.fold_left
      (fun st expected ->
        let st, act = Schedule.trigger st Schedule.Start in
        Alcotest.check action "Run to start the cycle" (Schedule.Run Start) act;
        let st, act = Schedule.finished st (Some (Outcome.Offline "x")) in
        (match act with
        | Schedule.Wait d ->
            Alcotest.(check (option int))
              "delay" (Some expected) (Ptime.Span.to_int_s d)
        | _ -> Alcotest.fail "expected Wait");
        st)
      idle0 delays
  in
  (* A success after the run resets the attempt counter: the next failure
     waits 10s again. *)
  let st, _ = Schedule.trigger idle0 Schedule.Start in
  let st, _ = Schedule.finished st None in
  Alcotest.check state "reset to Idle {0}" idle0 st;
  let st, _ = Schedule.trigger st Schedule.Start in
  let _, act = Schedule.finished st (Some (Outcome.Offline "x")) in
  match act with
  | Schedule.Wait d ->
      Alcotest.(check (option int))
        "10s again" (Some 10) (Ptime.Span.to_int_s d)
  | _ -> Alcotest.fail "expected Wait"

let schedule_waiting_local_write_runs_keeping_the_attempt () =
  let waiting = Schedule.Waiting {attempt = 3} in
  let st, act = Schedule.trigger waiting Schedule.Local_write in
  Alcotest.check state "Running, attempt kept"
    (Schedule.Running {attempt = 3; again = None; background = false})
    st;
  Alcotest.check action "Run" (Schedule.Run Local_write) act

let schedule_signed_out_then_signed_in () =
  let st, _ = Schedule.trigger idle0 Schedule.Start in
  let st, act = Schedule.finished st (Some Outcome.Signed_out) in
  Alcotest.check state "Idle {0}" idle0 st;
  Alcotest.check action "Nothing" Schedule.Nothing act;
  let _, act = Schedule.trigger st Schedule.Signed_in in
  Alcotest.check action "Signed_in runs a cycle" (Schedule.Run Signed_in) act

let schedule_waiting_backgrounded_then_resume () =
  let waiting = Schedule.Waiting {attempt = 2} in
  let st, act = Schedule.trigger waiting Schedule.Backgrounded in
  Alcotest.check state "Idle, attempt kept" (Schedule.Idle {attempt = 2}) st;
  Alcotest.check action "Cancel_timer" Schedule.Cancel_timer act;
  let _, act = Schedule.trigger st Schedule.Resume in
  Alcotest.check action "Resume runs a cycle" (Schedule.Run Resume) act

(* Every sequence of up to 6 events (the seven triggers, plus [finished] fed
   only when the state is [Running], with [None], [Some (Offline _)] and
   [Some Signed_out]): no [Run] is ever returned while the state before the
   event was already [Running], except by [finished]; every [Run] leaves the
   state [Running]; a trigger's [Run] carries that trigger. *)
let schedule_exhaustive_invariants () =
  let triggers =
    [
      Schedule.Start;
      Resume;
      Local_write;
      Signed_in;
      Manual;
      Retry_timer;
      Backgrounded;
    ]
  in
  let finished_variants =
    [None; Some (Outcome.Offline "x"); Some Outcome.Signed_out]
  in
  let is_running = function
    | Schedule.Running _ -> true
    | Idle _ | Waiting _ -> false
  in
  let rec go depth st =
    match depth > 6 with
    | true -> ()
    | false -> (
        List.iter
          (fun t ->
            let was_running = is_running st in
            let st', act = Schedule.trigger st t in
            (match act with
            | Schedule.Run run ->
                Alcotest.(check bool)
                  "a trigger's Run never starts from an already-Running state"
                  true (not was_running);
                Alcotest.(check bool)
                  "Run leaves the state Running" true (is_running st');
                Alcotest.(check bool)
                  "a trigger's Run carries that trigger" true
                  (Schedule.equal_trigger run t)
            | Wait _ | Cancel_timer | Nothing -> ());
            go (depth + 1) st')
          triggers;
        match is_running st with
        | false -> ()
        | true ->
            List.iter
              (fun stop ->
                let st', act = Schedule.finished st stop in
                (match act with
                | Schedule.Run (_ : Schedule.trigger) ->
                    Alcotest.(check bool)
                      "finished's Run leaves the state Running" true
                      (is_running st')
                | Wait _ | Cancel_timer | Nothing -> ());
                go (depth + 1) st')
              finished_variants)
  in
  go 0 Schedule.initial

let schedule_tests =
  let case name f = Alcotest.test_case name `Quick f in
  [
    case "trigger: every row of the mli's table" schedule_trigger_table;
    case "finished: every row of the mli's table" schedule_finished_table;
    case "Local_write during a cycle runs exactly one more after it"
      schedule_local_write_during_a_cycle_runs_once_more;
    case "six failures back off 10..300s, capped, then reset by a success"
      schedule_six_failures_back_off_then_cap_then_reset;
    case "Waiting + Local_write runs at once, attempt kept"
      schedule_waiting_local_write_runs_keeping_the_attempt;
    case "Signed_out idles with no retry; Signed_in restarts"
      schedule_signed_out_then_signed_in;
    case "Waiting + Backgrounded cancels the timer; Resume restarts"
      schedule_waiting_backgrounded_then_resume;
    case "Backgrounded during a failing cycle arms no timer"
      schedule_backgrounded_during_a_failing_cycle_arms_no_timer;
    case
      "exhaustive over sequences of <= 6 events: no stray Run, every Run \
       leaves Running"
      schedule_exhaustive_invariants;
  ]

(* ---------- Outcome ---------- *)

let outcome_retries_false_only_for_signed_out () =
  let cases =
    [
      Outcome.Signed_out;
      Auth "x";
      Offline "x";
      Paused;
      Unauthorized;
      Transient 503;
      Rejected 404;
      Bad_response "x";
      Store "x";
      Held "x";
    ]
  in
  List.iter
    (fun s ->
      Alcotest.(check bool)
        (Outcome.to_string s)
        (* Listed, not a wildcard: a new constructor must be added to
           [cases] above and decided here. *)
        (match s with
        | Outcome.Signed_out -> false
        | Auth _ | Offline _ | Paused | Unauthorized | Transient _ | Rejected _
        | Bad_response _ | Store _ | Held _ ->
            true)
        (Outcome.retries s))
    cases

let outcome_to_string_of_each_constructor () =
  Alcotest.(check string)
    "Signed_out" "signed out"
    (Outcome.to_string Signed_out);
  Alcotest.(check string) "Paused" "paused" (Outcome.to_string Paused);
  Alcotest.(check string)
    "Unauthorized" "HTTP 401"
    (Outcome.to_string Unauthorized);
  Alcotest.(check string)
    "Transient 503" "HTTP 503"
    (Outcome.to_string (Transient 503));
  Alcotest.(check string)
    "Rejected 404" "HTTP 404"
    (Outcome.to_string (Rejected 404));
  List.iter
    (fun (expected, s) ->
      Alcotest.(check string) expected expected (Outcome.to_string s))
    [
      ("auth: x", Outcome.Auth "x");
      ("offline: x", Outcome.Offline "x");
      ("bad response: x", Outcome.Bad_response "x");
      ("store: x", Outcome.Store "x");
      ("push held: x", Outcome.Held "x");
    ]

let outcome_persistent_only_for_rejected_bad_response_store () =
  List.iter
    (fun (s, expected) ->
      Alcotest.(check bool)
        (Outcome.to_string s) expected (Outcome.persistent s))
    [
      (Outcome.Signed_out, false);
      (Auth "x", false);
      (Offline "x", false);
      (Paused, false);
      (Unauthorized, false);
      (Transient 503, false);
      (Rejected 404, true);
      (Bad_response "x", true);
      (Store "x", true);
      (Held "x", false);
    ]

let outcome_tests =
  let case name f = Alcotest.test_case name `Quick f in
  [
    case "persistent only for Rejected, Bad_response, Store"
      outcome_persistent_only_for_rejected_bad_response_store;
    case "retries is false only for Signed_out"
      outcome_retries_false_only_for_signed_out;
    case "to_string of each constructor" outcome_to_string_of_each_constructor;
  ]

(* ---------- Last_error ---------- *)

let last_error = Alcotest.testable Last_error.pp Last_error.equal

let last_error_tests =
  let case name f = Alcotest.test_case name `Quick f in
  [
    case "to_string, then of_string, gives the value back" (fun () ->
        List.iter
          (fun e ->
            Alcotest.check last_error (Last_error.to_string e) e
              (Last_error.of_string (Last_error.to_string e)))
          [
            Last_error.Rejected 409;
            Rejected 400;
            Invalid "unknown table nope";
            Invalid "plants payload: x";
            Other "offline: boom";
          ]);
    case "the written shapes" (fun () ->
        Alcotest.(check string)
          "Rejected" "HTTP 409"
          (Last_error.to_string (Rejected 409));
        Alcotest.(check string)
          "Invalid" "invalid entry: why"
          (Last_error.to_string (Invalid "why")));
    case "of_string on other text: Other, unless it looks like a shape"
      (fun () ->
        List.iter
          (fun (text, expected) ->
            Alcotest.check last_error text expected (Last_error.of_string text))
          [
            ("", Other "");
            ("HTTP 409 Conflict", Other "HTTP 409 Conflict");
            ("HTTP x", Other "HTTP x");
            ("invalid entry: ", Invalid "");
            ("HTTP 500", Rejected 500);
          ]);
  ]

(* ---------- Report ---------- *)

(* The engine logs each cycle with Report.to_string ("sync: …" in the
   console, read on the device checks): its exact text is pinned. *)
let report_tests =
  let case name f = Alcotest.test_case name `Quick f in
  let started = Sync_fixtures.time "2026-11-12T09:00:00Z" in
  let table : Pull.table_report =
    {
      table = "tags";
      fetched = 3;
      inserted = 1;
      replaced = 1;
      unchanged = 0;
      kept_local = 1;
      repeated = true;
      cursor = None;
    }
  in
  let check what expected cycle =
    let r = {Report.trigger = Schedule.Resume; started; cycle} in
    Alcotest.(check string) what expected (Report.to_string r)
  in
  [
    case "a completed cycle: trigger, push counts, per-table pull counts"
      (fun () ->
        check "pushed, pulled"
          "resume; pushed 2, parked 1; pulled tags 3 (+1 ~1 =0 kept 1, \
           repeated)"
          (Pushed ({pushed = 2; parked = 1}, Done [table])));
    case "a stopped push: no pull line, the stop" (fun () ->
        check "push stopped" "resume; pushed 0, parked 0; stopped: paused"
          (Push_stopped ({pushed = 0; parked = 0}, Paused)));
    case "a stopped pull: the stop, which is also pull_stop" (fun () ->
        let cycle =
          Report.Pushed ({pushed = 1; parked = 0}, Stopped (Rejected 404))
        in
        check "pull stopped" "resume; pushed 1, parked 0; stopped: HTTP 404"
          cycle;
        let r = {Report.trigger = Schedule.Resume; started; cycle} in
        Alcotest.(check (option string))
          "pull_stop" (Some "HTTP 404")
          (Option.map Outcome.to_string (Report.pull_stop r)));
    case "a held push: the hold once, then the pull" (fun () ->
        check "held, pulled"
          "resume; push held: keep-alive: x; pulled tags 3 (+1 ~1 =0 kept 1, \
           repeated)"
          (Held ("keep-alive: x", Done [table]));
        check "held, pull stopped"
          "resume; push held: keep-alive: x; stopped: HTTP 404"
          (Held ("keep-alive: x", Stopped (Rejected 404))));
    case "stop, pull_stop and pulled_writes on every shape" (fun () ->
        let stop =
          Alcotest.(option (testable Outcome.pp_stop Outcome.equal_stop))
        in
        let no_writes = {table with inserted = 0; replaced = 0} in
        let shapes =
          [
            ( "push stopped",
              Report.Push_stopped ({pushed = 0; parked = 0}, Paused),
              (Some Outcome.Paused, None, false) );
            ( "pull stopped",
              Pushed ({pushed = 1; parked = 0}, Stopped (Rejected 404)),
              (Some (Outcome.Rejected 404), Some (Outcome.Rejected 404), false)
            );
            ( "pulled, rows written",
              Pushed ({pushed = 0; parked = 0}, Done [table]),
              (None, None, true) );
            ( "pulled, nothing written",
              Pushed ({pushed = 0; parked = 0}, Done [no_writes]),
              (None, None, false) );
            ( "held, pulled",
              Held ("x", Done [table]),
              (Some (Outcome.Held "x"), None, true) );
            ( "held, pull stopped",
              Held ("x", Stopped (Rejected 404)),
              (Some (Outcome.Rejected 404), Some (Outcome.Rejected 404), false)
            );
          ]
        in
        List.iter
          (fun (what, cycle, (expected_stop, expected_pull_stop, writes)) ->
            let r = {Report.trigger = Schedule.Resume; started; cycle} in
            Alcotest.check stop (what ^ ": stop") expected_stop (Report.stop r);
            Alcotest.check stop (what ^ ": pull_stop") expected_pull_stop
              (Report.pull_stop r);
            Alcotest.(check bool)
              (what ^ ": pulled_writes") writes (Report.pulled_writes r))
          shapes);
  ]

let () =
  Alcotest.run "sync cycle"
    [
      ("Synced", synced_tests);
      ("Push", push_tests);
      ("Pull", pull_tests);
      ("Schedule", schedule_tests);
      ("Outcome", outcome_tests);
      ("Last_error", last_error_tests);
      ("Report", report_tests);
    ]
