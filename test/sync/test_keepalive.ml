(* Native alcotest of app/sync_core/keepalive/wire.ml and report.ml, the
   contract between the app and web/runner/keepalive.js; it also decodes
   what the job's node test (test/runner/test_keepalive.mjs) writes. *)

module Testable = Herbier_test_support.Testable
module Session = Herbier_sync_core.Auth.Session
module Gotrue = Herbier_sync_core.Auth.Gotrue
module Synced = Herbier_sync_core.Synced
module Rest = Herbier_sync_core.Net.Rest
module Keepalive = Herbier_sync_core.Keepalive
module Outbox = Herbier_store.Outbox
module F = Sync_fixtures
module Wire = Keepalive.Wire
module Report = Keepalive.Report
module Text = Herbier_test_support.Text

(* supabase_url matches test/sync/handoff_sample.ml's; apikey is "K", the key
   of Sync_fixtures.conn, for the cross-check against Mock_http. *)
let supabase_url = "http://127.0.0.1:54321"
let apikey = "K"

(* ---------- small helpers ---------- *)

let json = Testable.yojson

let check_request name a b =
  Alcotest.check json name (Wire.request_to_yojson a) (Wire.request_to_yojson b)

let has_header_ci name headers =
  List.exists
    (fun (k, _) ->
      String.equal (String.lowercase_ascii k) (String.lowercase_ascii name))
    headers

let header_value_ci name headers =
  List.find_map
    (fun (k, v) ->
      match
        String.equal (String.lowercase_ascii k) (String.lowercase_ascii name)
      with
      | true -> Some v
      | false -> None)
    headers

(* One outbox entry with no row behind it: entry_stmt accepts any table name
   and payload (test/store's entry_stmt_is_read_back_by_next does the same),
   which is exactly what the "unknown table" / "wrong shape" cases need. *)
let entry_of stmt =
  let db = Sqlite_cli.migrated_db () in
  let (_ : int) = Sqlite_cli.write_ok "entry" db stmt in
  match Sqlite_cli.all db (Outbox.next ~limit:1) with
  | [e] -> e
  | es -> Alcotest.failf "expected exactly one entry, got %d" (List.length es)

let one_entry table_name row_id payload =
  entry_of (Outbox.entry_stmt ~table_name ~row_id payload)

(* ---------- one row per synced table ---------- *)

let t1 = F.time "2026-11-01T10:00:00Z"
let plant_min = F.plant ~at:t1 1 "Digitale"
let tag_min = F.tag ~at:t1 1 "Vivace"
let entry_for t row = entry_of (F.entry_stmt t row)

(* One entry per synced table, in Synced.all's order. *)
let samples =
  lazy
    [
      entry_for Synced.plants plant_min;
      entry_for Synced.tags tag_min;
      entry_for Synced.observations (F.observation ~at:t1 1);
      entry_for Synced.photos (F.photo ~at:t1 ~observation:1 1);
      entry_for Synced.plant_tags (F.plant_tag ~at:t1 ~plant:1 ~tag:1 1);
      entry_for Synced.plant_refs (F.plant_ref ~at:t1 ~plant:1 1);
      entry_for Synced.reference (F.reference ~at:t1 ~plant:1 1);
    ]

(* ---------- push_request vs. Rest.Make (Mock_http).upsert ---------- *)

let push_via_mock table_name payload =
  Mock_http.reset ();
  Mock_http.respond ~status:201 "";
  (match Synced.decode_entry ~table_name payload with
  | Error e ->
      Alcotest.failf "decode_entry: %s" (Synced.entry_error_to_string e)
  | Ok (Entry (t, row)) -> (
      match F.R.upsert F.conn t row with
      | Ok () -> ()
      | Error e -> Alcotest.failf "R.upsert failed: %s" (F.R.error_to_string e)));
  Mock_http.last ()

let compare_push_request name (req : Wire.request) (m : Mock_http.request) =
  Alcotest.(check string)
    (name ^ ": method")
    (Mock_http.string_of_meth m.meth)
    (Mock_http.string_of_meth req.meth);
  Alcotest.(check string)
    (name ^ ": path and query")
    (Mock_http.decoded_target m.url)
    (Mock_http.decoded_target (Uri.of_string req.url));
  let norm hs =
    hs
    |> List.filter (fun (k, _) ->
        not (String.equal (String.lowercase_ascii k) "authorization"))
    |> List.map (fun (k, v) -> (String.lowercase_ascii k, v))
    |> List.sort compare
  in
  Alcotest.(check (list (pair string string)))
    (name ^ ": headers, minus authorization")
    (norm m.headers) (norm req.headers);
  let body_json = function
    | None -> `Null
    | Some s -> Yojson.Safe.from_string s
  in
  Alcotest.check json (name ^ ": body") (body_json m.body) (body_json req.body)

let push_request_matches_rest_upsert_for_every_table () =
  Alcotest.(check (list string))
    "one sample per synced table"
    (List.map (fun (Synced.Any t) -> Synced.name t) Synced.all)
    (List.map (fun (e : Outbox.entry) -> e.table_name) (Lazy.force samples));
  List.iter
    (fun (entry : Outbox.entry) ->
      let name = entry.table_name in
      match Wire.push_request ~supabase_url ~apikey entry with
      | Error msg -> Alcotest.failf "%s: push_request failed: %s" name msg
      | Ok req ->
          let m = push_via_mock name entry.payload in
          compare_push_request name req m;
          Alcotest.(check bool)
            (name ^ ": no authorization header")
            false
            (has_header_ci "authorization" req.headers);
          Alcotest.(check (option string))
            (name ^ ": apikey") (Some apikey)
            (header_value_ci "apikey" req.headers))
    (Lazy.force samples)

let push_request_ignores_a_trailing_slash () =
  let entry = entry_for Synced.plants plant_min in
  let a = Wire.push_request ~supabase_url ~apikey entry in
  let b = Wire.push_request ~supabase_url:(supabase_url ^ "/") ~apikey entry in
  match (a, b) with
  | Ok ra, Ok rb ->
      check_request "same request" ra rb;
      Alcotest.(check bool) "equal_request" true (Wire.equal_request ra rb)
  | Error e, _ | _, Error e -> Alcotest.failf "expected Ok, got Error %s" e

(* The reason the engine parks an entry with. *)
let park_reason (e : Outbox.entry) =
  match Synced.decode_entry ~table_name:e.table_name e.payload with
  | Error err -> Synced.entry_error_to_string err
  | Ok _ -> Alcotest.fail "expected an entry that does not decode"

let push_request_unknown_table_is_error () =
  let entry = one_entry "nope" "row-x" (`Assoc []) in
  match Wire.push_request ~supabase_url ~apikey entry with
  | Error why -> Alcotest.(check string) "park reason" (park_reason entry) why
  | Ok _ -> Alcotest.fail "expected Error"

let push_request_bad_payload_shape_is_error () =
  let bad_payload =
    match Postgrest.Input.to_json (Synced.input Synced.plants plant_min) with
    | `Assoc kvs -> `Assoc (List.remove_assoc "display_name" kvs)
    | _ -> Alcotest.fail "plant payload is not an object"
  in
  let entry =
    one_entry "plants" (Synced.id Synced.plants plant_min) bad_payload
  in
  match Wire.push_request ~supabase_url ~apikey entry with
  | Error why -> Alcotest.(check string) "park reason" (park_reason entry) why
  | Ok _ -> Alcotest.fail "expected Error"

(* ---------- ping_request ---------- *)

let ping_request_shape () =
  let req = Wire.ping_request ~supabase_url ~apikey in
  Alcotest.(check string) "method" "GET" (Mock_http.string_of_meth req.meth);
  let u = Uri.of_string req.url in
  Alcotest.(check string) "path" "/rest/v1/tags" (Uri.path u);
  let params = Uri.query u in
  Alcotest.(check (option (list string)))
    "select=id" (Some ["id"])
    (List.assoc_opt "select" params);
  Alcotest.(check (option (list string)))
    "id=eq.nil" (Some ["eq.00000000-0000-0000-0000-000000000000"])
    (List.assoc_opt "id" params);
  Alcotest.(check bool)
    "no authorization" false
    (has_header_ci "authorization" req.headers);
  Alcotest.(check (option string))
    "apikey" (Some apikey)
    (header_value_ci "apikey" req.headers)

let ping_fixture_is_an_empty_array () =
  let body =
    Sqlite_cli.read_file "../fixtures/sync_select_tags_keepalive_200.json"
  in
  match Yojson.Safe.from_string body with
  | `List [] -> ()
  | j -> Alcotest.failf "expected [], got %s" (Yojson.Safe.to_string j)

(* ---------- session_doc / queue_doc ---------- *)

let session_sample : Session.t =
  {
    access_token = "the-access-token";
    refresh_token = "the-refresh-token";
    expires_at = t1;
    user_id = "00000000-0000-7000-8000-000000000099";
    email = Some "me@herbier.local";
  }

(* What session_doc_bytes pins, tied to the code it comes from. *)
let session_doc_shape () =
  let doc = Wire.session_doc ~supabase_url ~apikey session_sample in
  let field name = function
    | `Assoc kvs -> (
        match List.assoc_opt name kvs with
        | Some j -> j
        | None -> Alcotest.failf "no %s field" name)
    | _ -> Alcotest.failf "%s: not in an object" name
  in
  let root = Yojson.Safe.from_string doc in
  let backend = field "backend" root in
  Alcotest.check json "backend.ping is ping_request"
    (Wire.request_to_yojson (Wire.ping_request ~supabase_url ~apikey))
    (field "ping" backend);
  Alcotest.check json "backend.refresh.url is Gotrue.refresh_grant's"
    (`String
       (Gotrue.refresh_grant ~base_url:supabase_url ~apikey ~refresh_token:"")
         .url)
    (field "url" (field "refresh" backend));
  match Session.of_json (field "session" root) with
  | Ok s ->
      Alcotest.(check bool)
        "session round-trips" true
        (Session.equal s session_sample)
  | Error e -> Alcotest.failf "session field did not decode: %s" e

let session_doc_hides_tokens_outside_the_session_field () =
  let doc = Wire.session_doc ~supabase_url ~apikey session_sample in
  match Yojson.Safe.from_string doc with
  | `Assoc kvs ->
      let session_field =
        match List.assoc_opt "session" kvs with
        | Some j -> j
        | None -> Alcotest.fail "no session field"
      in
      let rest_text =
        Yojson.Safe.to_string (`Assoc (List.remove_assoc "session" kvs))
      in
      Alcotest.(check bool)
        "no access token outside session" false
        (Text.contains ~sub:session_sample.access_token rest_text);
      Alcotest.(check bool)
        "no refresh token outside session" false
        (Text.contains ~sub:session_sample.refresh_token rest_text);
      let session_text = Yojson.Safe.to_string session_field in
      Alcotest.(check bool)
        "sanity: the session field does carry the access token" true
        (Text.contains ~sub:session_sample.access_token session_text)
  | _ -> Alcotest.fail "session_doc is not a JSON object"

let three_entries () =
  let db = Sqlite_cli.migrated_db () in
  let add stmt = ignore (Sqlite_cli.write_ok "entry" db stmt : int) in
  add (F.entry_stmt Synced.plants plant_min);
  add (F.entry_stmt Synced.tags tag_min);
  add (F.entry_stmt Synced.observations (F.observation ~at:t1 1));
  Sqlite_cli.all db (Outbox.next ~limit:3)

let requests_of doc =
  match Yojson.Safe.from_string doc with
  | `Assoc kvs -> (
      match List.assoc_opt "requests" kvs with
      | Some (`List reqs) -> reqs
      | _ -> Alcotest.fail "no requests array")
  | _ -> Alcotest.fail "queue_doc is not a JSON object"

let skipped_seq = Option.map (fun (s : Wire.skipped) -> s.seq)

let check_matches_push_request name entries reqs =
  List.iter2
    (fun (e : Outbox.entry) req_json ->
      match Wire.push_request ~supabase_url ~apikey e with
      | Ok r -> Alcotest.check json name (Wire.request_to_yojson r) req_json
      | Error msg -> Alcotest.failf "push_request failed: %s" msg)
    entries reqs

let queue_doc_of_no_entries_is_empty () =
  let {Wire.doc; count; skipped} = Wire.queue_doc ~supabase_url ~apikey [] in
  Alcotest.(check (option int)) "no skipped" None (skipped_seq skipped);
  Alcotest.(check int) "count" 0 count;
  Alcotest.(check int) "no requests" 0 (List.length (requests_of doc))

let queue_doc_of_three_valid_entries () =
  let entries = three_entries () in
  let {Wire.doc; count; skipped} =
    Wire.queue_doc ~supabase_url ~apikey entries
  in
  Alcotest.(check (option int)) "no skipped" None (skipped_seq skipped);
  Alcotest.(check int) "count" 3 count;
  let reqs = requests_of doc in
  Alcotest.(check int) "3 requests, in order" 3 (List.length reqs);
  check_matches_push_request "matches push_request" entries reqs

(* Entries in the outbox in this order: [`Good] a valid plant or tag,
   [`Bad] an unknown table. *)
let outbox_of kinds =
  let db = Sqlite_cli.migrated_db () in
  let stmts =
    List.mapi
      (fun i kind ->
        match kind with
        | `Good ->
            F.entry_stmt Synced.tags
              (F.tag ~at:t1 (10_000 + i + 1) (Printf.sprintf "Tag %d" (i + 1)))
        | `Bad ->
            Outbox.entry_stmt ~table_name:"nope"
              ~row_id:(Printf.sprintf "row-%d" i)
              (`Assoc []))
      kinds
  in
  Sqlite_cli.exec_ok "entries" db
    ("begin;\n"
    ^ String.concat "" (List.map Sqlite_cli.inline stmts)
    ^ "commit;\n");
  let n = List.length kinds in
  let entries = Sqlite_cli.all db (Outbox.next ~limit:n) in
  Alcotest.(check int) "entries present" n (List.length entries);
  entries

let seq_at entries i = Outbox.seq_to_int (List.nth entries i).Outbox.seq

let queue_doc_stops_at_a_bad_entry () =
  let entries = outbox_of [`Good; `Bad; `Good] in
  let {Wire.doc; count; skipped} =
    Wire.queue_doc ~supabase_url ~apikey entries
  in
  Alcotest.(check (option int))
    "skipped"
    (Some (seq_at entries 1))
    (skipped_seq skipped);
  Alcotest.(check (option string))
    "skipped why: the park reason"
    (Some (park_reason (List.nth entries 1)))
    (Option.map (fun (s : Wire.skipped) -> s.why) skipped);
  Alcotest.(check int) "count: the entry before the bad one" 1 count;
  Alcotest.(check int) "one request" 1 (List.length (requests_of doc))

let queue_doc_of_a_bad_first_entry_is_empty () =
  let entries = outbox_of [`Bad; `Good] in
  let {Wire.doc; count; skipped} =
    Wire.queue_doc ~supabase_url ~apikey entries
  in
  Alcotest.(check (option int))
    "skipped"
    (Some (seq_at entries 0))
    (skipped_seq skipped);
  Alcotest.(check int) "count" 0 count;
  Alcotest.(check int) "no request" 0 (List.length (requests_of doc))

let queue_doc_caps_at_queue_limit () =
  let entries = outbox_of (List.init 250 (fun _ -> `Good)) in
  let {Wire.doc; count; skipped} =
    Wire.queue_doc ~supabase_url ~apikey entries
  in
  Alcotest.(check (option int)) "no skipped" None (skipped_seq skipped);
  Alcotest.(check int) "count" Wire.queue_limit count;
  let reqs = requests_of doc in
  Alcotest.(check int)
    "exactly queue_limit requests" Wire.queue_limit (List.length reqs);
  check_matches_push_request "matches push_request, the first 200"
    (List.filteri (fun i _ -> i < Wire.queue_limit) entries)
    reqs

let queue_doc_never_looks_past_the_limit () =
  let entries =
    outbox_of (List.init Wire.queue_limit (fun _ -> `Good) @ [`Bad])
  in
  let {Wire.doc; count; skipped} =
    Wire.queue_doc ~supabase_url ~apikey entries
  in
  Alcotest.(check (option int)) "nothing skipped" None (skipped_seq skipped);
  Alcotest.(check int) "count" Wire.queue_limit count;
  Alcotest.(check int)
    "requests" Wire.queue_limit
    (List.length (requests_of doc))

let queue_doc_contains_no_token () =
  let entries = three_entries () in
  let {Wire.doc; _} = Wire.queue_doc ~supabase_url ~apikey entries in
  Alcotest.(check bool)
    "no access token" false
    (Text.contains ~sub:session_sample.access_token doc);
  Alcotest.(check bool)
    "no refresh token" false
    (Text.contains ~sub:session_sample.refresh_token doc)

(* ---------- decode_reclaim ---------- *)

let decode_reclaim_cases () =
  let check name expected text =
    Alcotest.(check (result bool string))
      name expected (Wire.decode_reclaim text)
  in
  check "nothing in flight" (Ok false) {|{"v":1,"in_flight":false}|};
  check "in flight" (Ok true) {|{"v":1,"in_flight":true}|}

(* ---------- Report.decode / Wire.decode_taken_session, cross-checked against
   test/runner's node test output ---------- *)

let report_json = lazy (Sqlite_cli.read_file "../runner/report.json")
let kv_after_json = lazy (Sqlite_cli.read_file "../runner/kv_after.json")

let report_with_session_json =
  lazy (Sqlite_cli.read_file "../runner/report_with_session.json")

let lines_json =
  lazy
    (match Yojson.Safe.from_file "../runner/lines.json" with
    | `List lines ->
        List.map
          (function
            | `String l -> l | _ -> Alcotest.fail "lines.json: not a string")
          lines
    | _ -> Alcotest.fail "lines.json is not an array")

(* A run without its clock, readable in a failure message. *)
let run_summary (r : Report.run) =
  let session =
    match r.session with
    | Report.No_session -> "none"
    | Fresh -> "fresh"
    | Refreshed -> "refreshed"
    | Replaced -> "replaced"
    | Revoked status -> Printf.sprintf "revoked %d" status
    | Refresh_failed why -> "refresh_failed " ^ why
  in
  let queue =
    match r.queue with
    | Report.Not_run -> "not run"
    | Skipped_app_active -> "skipped"
    | Pushed {count; stop} ->
        Printf.sprintf "pushed %d%s" count
          (match stop with Some why -> " stop " ^ why | None -> "")
  in
  let ping =
    match r.ping with
    | Report.Ping_status status -> string_of_int status
    | Ping_failed why -> "failed " ^ why
    | Ping_not_run -> "not run"
  in
  Printf.sprintf "%s %s active=%b queue=%s error=%s ping=%s"
    (Report.trigger_to_string r.trigger)
    session r.app_active queue
    (Option.value r.error ~default:"-")
    ping

(* The runs of test/runner/test_keepalive.mjs's last test, newest first, each
   constructor of [session_outcome], [queue] and [ping] reached from its JS
   spelling. *)
let report_decode_decodes_the_js_report () =
  match Report.decode (Lazy.force report_json) with
  | Error e -> Alcotest.failf "Report.decode failed: %s" e
  | Ok r -> (
      Alcotest.(check bool)
        "the session in KV is unreadable: no expiry" true
        (Option.is_none r.session_expires_at);
      Alcotest.(check int) "nothing queued" 0 r.queued;
      Alcotest.(check (list string))
        "every outcome, newest first"
        [
          "job none active=false queue=not run error=bad session in KV \
           ping=not run";
          "dispatch none active=false queue=not run error=- ping=not run";
          "job revoked 400 active=false queue=not run error=- ping=not run";
          "job refreshed active=false queue=pushed 0 error=- ping=200";
          "job refresh_failed HTTP 503 active=false queue=not run error=- \
           ping=not run";
          "job replaced active=false queue=not run error=- ping=not run";
          "job fresh active=false queue=pushed 0 error=- ping=failed network: \
           ping: network unreachable";
          "job fresh active=true queue=skipped error=- ping=200";
          "job fresh active=false queue=pushed 0 error=- ping=401";
          "job fresh active=false queue=pushed 1 stop HTTP 409 error=- ping=200";
          "job fresh active=false queue=pushed 3 error=- ping=200";
          "job none active=false queue=not run error=- ping=not run";
        ]
        (List.map run_summary r.runs);
      (* The first run is at the node test's NOT_DUE_NOW: 10 minutes before
         handoff_sample.ml's expires_at, 2026-11-12T10:00:00Z. *)
      match List.rev r.runs with
      | oldest :: _ ->
          Alcotest.(check string)
            "at, read as milliseconds" "2026-11-12T09:50:00Z"
            (Ptime.to_rfc3339 ~tz_offset_s:0 oldest.at)
      | [] -> Alcotest.fail "no run")

let report_decode_reads_a_session_expiry_in_seconds () =
  match Report.decode (Lazy.force report_with_session_json) with
  | Error e -> Alcotest.failf "Report.decode failed: %s" e
  | Ok r ->
      Alcotest.(check (option string))
        "handoff_sample.ml's expires_at" (Some "2026-11-12T10:00:00Z")
        (Option.map (Ptime.to_rfc3339 ~tz_offset_s:0) r.session_expires_at);
      Alcotest.(check int) "queued" 3 r.queued

(* The lines the job printed are run_to_string's, run for run. *)
let run_to_string_is_the_jobs_line () =
  match Report.decode (Lazy.force report_json) with
  | Error e -> Alcotest.failf "Report.decode failed: %s" e
  | Ok r ->
      Alcotest.(check (list string))
        "the job's console lines, oldest first" (Lazy.force lines_json)
        (List.rev_map Report.run_to_string r.runs)

let report_text ?(top = "") run =
  Printf.sprintf {|{"v":1,"session_expires_at":null,"queued":0,"runs":[%s]%s}|}
    run top

let a_run fields =
  Printf.sprintf {|{"at":1794477600000,"trigger":"job","app_active":false,%s}|}
    fields

let ok_fields = {|"session":"none","queue":null,"error":null,"ping":null|}

let report_decode_unknown_fields_ignored () =
  match
    Report.decode
      (report_text ~top:{|,"another_unknown_field":true|}
         (a_run (ok_fields ^ {|,"an_unknown_field":42|})))
  with
  | Ok r -> Alcotest.(check int) "one run" 1 (List.length r.runs)
  | Error e -> Alcotest.failf "Report.decode failed: %s" e

let report_decode_reads_only_the_outcomes_field () =
  match
    Report.decode
      (report_text
         (a_run
            {|"session":"fresh","revoked_status":"x","refresh_error":1,"queue":null,"error":null,"ping":null|}))
  with
  | Ok {runs = [{session = Fresh; _}]; _} -> ()
  | Ok _ -> Alcotest.fail "expected one fresh run"
  | Error e -> Alcotest.failf "Report.decode failed: %s" e

let report_decode_reads_a_float_clock () =
  match
    Report.decode
      (report_text
         (Printf.sprintf
            {|{"at":1794477600000.0,"trigger":"job","app_active":false,%s}|}
            ok_fields))
  with
  | Ok {runs = [run]; _} ->
      Alcotest.(check string)
        "at" "2026-11-12T10:00:00Z"
        (Ptime.to_rfc3339 ~tz_offset_s:0 run.at)
  | Ok _ -> Alcotest.fail "expected one run"
  | Error e -> Alcotest.failf "Report.decode failed: %s" e

let report_decode_reads_a_session_expiry () =
  match
    Report.decode
      {|{"v":1,"session_expires_at":1794477600,"queued":2,"runs":[]}|}
  with
  | Ok r ->
      Alcotest.(check (option string))
        "seconds" (Some "2026-11-12T10:00:00Z")
        (Option.map (Ptime.to_rfc3339 ~tz_offset_s:0) r.session_expires_at);
      Alcotest.(check int) "queued" 2 r.queued
  | Error e -> Alcotest.failf "Report.decode failed: %s" e

let decode_taken_session_of_null_is_none () =
  match Wire.decode_taken_session {|{"v":1,"session":null}|} with
  | Ok None -> ()
  | Ok (Some _) -> Alcotest.fail "expected None"
  | Error e -> Alcotest.failf "Wire.decode_taken_session failed: %s" e

let decode_taken_session_of_the_js_refresh () =
  match Wire.decode_taken_session (Lazy.force kv_after_json) with
  | Error e -> Alcotest.failf "Wire.decode_taken_session failed: %s" e
  | Ok None -> Alcotest.fail "expected Some"
  | Ok (Some (s : Session.t)) -> (
      let fixture =
        Yojson.Safe.from_file "../fixtures/gotrue_token_refresh_200.json"
      in
      match fixture with
      | `Assoc kvs ->
          let str k =
            match List.assoc k kvs with
            | `String v -> v
            | _ -> Alcotest.failf "fixture field %s is not a string" k
          in
          let expires_in =
            match List.assoc "expires_in" kvs with
            | `Int n -> n
            | _ -> Alcotest.fail "fixture expires_in is not an int"
          in
          Alcotest.(check string)
            "new access token" (str "access_token") s.access_token;
          Alcotest.(check string)
            "new refresh token" (str "refresh_token") s.refresh_token;
          (* test/runner/test_keepalive.mjs sends the refresh at a fixed
             Date.now() of 1_800_000_000_000 ms: expires_at = floor (sent_ms /
             1000) + expires_in. *)
          let expected =
            match
              Ptime.of_float_s (1_800_000_000. +. float_of_int expires_in)
            with
            | Some t -> t
            | None -> Alcotest.fail "bad expected expires_at"
          in
          Alcotest.(check bool)
            "expires_at = sent + expires_in" true
            (Ptime.equal expected s.expires_at)
      | _ -> Alcotest.fail "fixture is not an object")

let run_to_string_is_the_documented_line () =
  let run : Report.run =
    {
      at = F.time "2026-11-12T10:00:00Z";
      trigger = Job;
      app_active = false;
      session = Report.Refreshed;
      queue = Pushed {count = 3; stop = None};
      error = None;
      ping = Report.Ping_status 200;
    }
  in
  Alcotest.(check string)
    "line" "2026-11-12T10:00:00Z job refreshed pushed 3 ping 200"
    (Report.run_to_string run)

(* The runs of the node test's report were made with handoff_sample.ml's
   session and then gotrue_token_refresh_200.json's: none of their lines
   may carry either session's tokens. *)
let run_to_string_contains_no_token () =
  let runs =
    match Report.decode (Lazy.force report_json) with
    | Ok r -> r.runs
    | Error e -> Alcotest.failf "Report.decode failed: %s" e
  in
  let refreshed =
    match Yojson.Safe.from_file "../fixtures/gotrue_token_refresh_200.json" with
    | `Assoc kvs ->
        List.filter_map
          (fun k ->
            match List.assoc_opt k kvs with
            | Some (`String v) -> Some v
            | _ -> None)
          ["access_token"; "refresh_token"]
    | _ -> Alcotest.fail "fixture is not an object"
  in
  let tokens = ["handoff-access-token"; "handoff-refresh-token"] @ refreshed in
  Alcotest.(check int) "both fixture tokens read" 4 (List.length tokens);
  List.iter
    (fun run ->
      let line = Report.run_to_string run in
      List.iter
        (fun token ->
          Alcotest.(check bool)
            ("no token in: " ^ line) false
            (Text.contains ~sub:token line))
        tokens)
    runs

(* ---------- the exact bytes and error texts ---------- *)

(* The documents' text, byte for byte: the job reads them by key, but these
   pins keep a change of encoder from changing what the job gets. *)
let session_doc_bytes () =
  Alcotest.(check string)
    "session_doc"
    {|{"backend":{"v":1,"supabase_url":"http://127.0.0.1:54321","apikey":"K","ping":{"method":"GET","url":"http://127.0.0.1:54321/rest/v1/tags?select=id&id=eq.00000000-0000-0000-0000-000000000000","headers":{"apikey":"K","accept":"application/json","prefer":"missing=default"},"body":null},"refresh":{"method":"POST","url":"http://127.0.0.1:54321/auth/v1/token?grant_type=refresh_token","headers":{"apikey":"K","content-type":"application/json"},"body":null},"logout":{"method":"POST","url":"http://127.0.0.1:54321/auth/v1/logout?scope=local","headers":{"apikey":"K"},"body":null}},"session":{"v":1,"access_token":"the-access-token","refresh_token":"the-refresh-token","expires_at":1793527200,"user_id":"00000000-0000-7000-8000-000000000099","email":"me@herbier.local"}}|}
    (Wire.session_doc ~supabase_url:(supabase_url ^ "/") ~apikey session_sample)

let queue_doc_bytes () =
  let {Wire.doc; _} = Wire.queue_doc ~supabase_url ~apikey (three_entries ()) in
  Alcotest.(check string)
    "queue_doc"
    {|{"v":1,"requests":[{"method":"POST","url":"http://127.0.0.1:54321/rest/v1/plants","headers":{"apikey":"K","prefer":"resolution=merge-duplicates,missing=default","content-type":"application/json"},"body":"{\"id\":\"01965d4e-0000-7000-8000-000000000001\",\"display_name\":\"Digitale\",\"aliases\":[],\"scientific_name\":null,\"authorship\":null,\"gbif_key\":null,\"notes\":\"\",\"notes_updated_at\":null,\"cover_photo_id\":null,\"created_at\":\"2026-11-01T10:00:00Z\",\"updated_at\":\"2026-11-01T10:00:00Z\",\"deleted_at\":null}"},{"method":"POST","url":"http://127.0.0.1:54321/rest/v1/tags","headers":{"apikey":"K","prefer":"resolution=merge-duplicates,missing=default","content-type":"application/json"},"body":"{\"id\":\"01965d4e-0000-7000-8000-000000000001\",\"name\":\"Vivace\",\"created_at\":\"2026-11-01T10:00:00Z\",\"updated_at\":\"2026-11-01T10:00:00Z\",\"deleted_at\":null}"},{"method":"POST","url":"http://127.0.0.1:54321/rest/v1/observations","headers":{"apikey":"K","prefer":"resolution=merge-duplicates,missing=default","content-type":"application/json"},"body":"{\"id\":\"01965d4e-0000-7000-8000-000000000001\",\"plant_id\":null,\"at\":\"2026-11-01T10:00:00Z\",\"lat\":null,\"lon\":null,\"accuracy_m\":null,\"place_label\":null,\"place_derived\":null,\"note\":null,\"created_at\":\"2026-11-01T10:00:00Z\",\"updated_at\":\"2026-11-01T10:00:00Z\",\"deleted_at\":null}"}]}|}
    doc

(* Every decoder's error text, as #dev/keepalive and the console show it. *)
let decode_error_texts () =
  let report run = Report.decode (report_text run) in
  let error = function Ok _ -> "Ok" | Error e -> e in
  Alcotest.(check (list string))
    "Report.decode"
    [
      "run 0: bad or missing at";
      "run 0: bad or missing revoked_status";
      "run 0: bad or missing refresh_error";
      "run 0: unknown session outcome";
      "run 0: bad or missing trigger";
      "run 0: bad or missing app_active";
      "run 0: bad or missing ping";
      "run 0: bad or missing queue";
      "run 0: bad or missing queue";
      "run 0: bad or missing queue";
      "run 0: bad or missing error";
      "run 0: bad or missing ping";
      "run 0: bad or missing session";
      "run 0: not an object";
      "not JSON";
      "not an object";
      "unknown version";
      "no version";
      "runs is not an array";
      "bad or missing runs";
      "bad or missing session_expires_at";
      "bad or missing queued";
    ]
    (List.map error
       [
         report
           (Printf.sprintf {|{"trigger":"job","app_active":false,%s}|} ok_fields);
         report
           (a_run {|"session":"revoked","queue":null,"error":null,"ping":null|});
         report
           (a_run
              {|"session":"refresh_failed","queue":null,"error":null,"ping":null|});
         report
           (a_run {|"session":"nope","queue":null,"error":null,"ping":null|});
         report
           (Printf.sprintf
              {|{"at":1794477600000,"trigger":"cron","app_active":false,%s}|}
              ok_fields);
         report
           (Printf.sprintf {|{"at":1794477600000,"trigger":"job",%s}|} ok_fields);
         report
           (a_run {|"session":"none","queue":null,"error":null,"ping":true|});
         report
           (a_run {|"session":"fresh","queue":"later","error":null,"ping":null|});
         report
           (a_run
              {|"session":"fresh","queue":{"pushed":1},"error":null,"ping":null|});
         report
           (a_run
              {|"session":"fresh","queue":{"pushed":-1,"stop":null},"error":null,"ping":null|});
         report (a_run {|"session":"none","queue":null,"ping":null|});
         report (a_run {|"session":"none","queue":null,"error":null|});
         report (a_run {|"session":5,"queue":null,"error":null,"ping":null|});
         report "42";
         Report.decode "not json at all";
         Report.decode "[]";
         Report.decode
           {|{"v":2,"session_expires_at":null,"queued":0,"runs":[]}|};
         Report.decode {|{"session_expires_at":null,"queued":0,"runs":[]}|};
         Report.decode
           {|{"v":1,"session_expires_at":null,"queued":0,"runs":{}}|};
         Report.decode {|{"v":1,"session_expires_at":null,"queued":0}|};
         Report.decode {|{"v":1,"session_expires_at":"x","queued":0,"runs":[]}|};
         Report.decode {|{"v":1,"session_expires_at":null,"runs":[]}|};
       ]);
  Alcotest.(check (list string))
    "Wire.decode_taken_session"
    [
      "not JSON";
      "user_id missing or ill-typed";
      "bad or missing session";
      "bad or missing session";
      "no version";
      "expires_at is not an int";
    ]
    (List.map
       (fun text -> error (Wire.decode_taken_session text))
       [
         "not json";
         {|{"v":1,"session":{"v":1}}|};
         {|{"v":1}|};
         {|{"v":1,"session":5}|};
         {|{"session":null}|};
         {|{"v":1,"session":{"v":1,"access_token":"A","refresh_token":"R","expires_at":"x","user_id":"u","email":null}}|};
       ]);
  Alcotest.(check (list string))
    "Wire.decode_reclaim"
    [
      "not JSON";
      "not an object";
      "no version";
      "unknown version";
      "bad or missing in_flight";
      "bad or missing in_flight";
    ]
    (List.map
       (fun text ->
         error (Result.map Bool.to_string (Wire.decode_reclaim text)))
       [
         "nope";
         "[]";
         {|{"in_flight":true}|};
         {|{"v":2,"in_flight":false}|};
         {|{"v":1,"in_flight":1}|};
         {|{"v":1}|};
       ])

(* ---------- the runner's configuration and the job's listeners ---------- *)

let config_matches_the_constants () =
  let config = Sqlite_cli.read_file "../../capacitor.config.ts" in
  let has needle =
    Alcotest.(check bool)
      ("capacitor.config.ts has " ^ needle)
      true
      (Text.contains ~sub:needle config)
  in
  has (Printf.sprintf "label: '%s'" Wire.label);
  has (Printf.sprintf "event: '%s'" (Wire.event_to_string Wire.Run));
  has (Printf.sprintf "interval: %d," Wire.interval_minutes)

let job_listens_to_every_event () =
  let job = Sqlite_cli.read_file "../../web/runner/keepalive.js" in
  List.iter
    (fun (event, how) ->
      let needle = Printf.sprintf "%s('%s'" how event in
      Alcotest.(check bool)
        ("keepalive.js: " ^ needle)
        true
        (Text.contains ~sub:needle job))
    [
      (Wire.event_to_string Wire.Run, "addEventListener");
      (Wire.event_to_string Wire.Run_now, "addEventListener");
      (Wire.event_to_string Wire.Set_session, "handle");
      (Wire.event_to_string Wire.Take_session, "handle");
      (Wire.event_to_string Wire.Hand_off, "handle");
      (Wire.event_to_string Wire.Reclaim, "handle");
      (Wire.event_to_string Wire.Report, "handle");
    ]

let () =
  Alcotest.run "keepalive"
    [
      ( "push_request",
        [
          ( "matches Rest.Make (Mock_http).upsert for every synced table, no \
             authorization header, apikey present",
            `Quick,
            push_request_matches_rest_upsert_for_every_table );
          ( "a trailing slash on supabase_url gives the same request",
            `Quick,
            push_request_ignores_a_trailing_slash );
          ( "an unknown table_name is Error",
            `Quick,
            push_request_unknown_table_is_error );
          ( "a payload of the wrong shape is Error",
            `Quick,
            push_request_bad_payload_shape_is_error );
        ] );
      ( "ping_request",
        [
          ("method, path, query, headers", `Quick, ping_request_shape);
          ( "the recorded 200 fixture is an empty array",
            `Quick,
            ping_fixture_is_an_empty_array );
        ] );
      ( "session_doc / queue_doc",
        [
          ( "session_doc: ping, refresh url, session round-trip",
            `Quick,
            session_doc_shape );
          ( "session_doc: no token outside the session field",
            `Quick,
            session_doc_hides_tokens_outside_the_session_field );
          ( "queue_doc of no entries is empty",
            `Quick,
            queue_doc_of_no_entries_is_empty );
          ( "queue_doc of 3 valid entries, in order, each matching push_request",
            `Quick,
            queue_doc_of_three_valid_entries );
          ( "queue_doc stops at a bad entry, returns it skipped",
            `Quick,
            queue_doc_stops_at_a_bad_entry );
          ( "queue_doc of a bad first entry is empty",
            `Quick,
            queue_doc_of_a_bad_first_entry_is_empty );
          ( "queue_doc caps at queue_limit, the first 200",
            `Quick,
            queue_doc_caps_at_queue_limit );
          ( "queue_doc never looks at an entry past the 200th",
            `Quick,
            queue_doc_never_looks_past_the_limit );
          ("queue_doc contains no token", `Quick, queue_doc_contains_no_token);
        ] );
      ("decode_reclaim", [("answers", `Quick, decode_reclaim_cases)]);
      ( "exact bytes and error texts",
        [
          ("session_doc", `Quick, session_doc_bytes);
          ("queue_doc", `Quick, queue_doc_bytes);
          ("decoders' errors", `Quick, decode_error_texts);
        ] );
      ( "Report.decode / Wire.decode_taken_session (cross-check with \
         test/runner)",
        [
          ( "decodes the node test's report.json",
            `Quick,
            report_decode_decodes_the_js_report );
          ( "reads the node test's session expiry, in seconds",
            `Quick,
            report_decode_reads_a_session_expiry_in_seconds );
          ( "unknown fields are ignored",
            `Quick,
            report_decode_unknown_fields_ignored );
          ( "a clock written as a float",
            `Quick,
            report_decode_reads_a_float_clock );
          ( "a session expiry, in seconds",
            `Quick,
            report_decode_reads_a_session_expiry );
          ( "a field only another outcome uses is not read",
            `Quick,
            report_decode_reads_only_the_outcomes_field );
          ( "Wire.decode_taken_session of a null session is Ok None",
            `Quick,
            decode_taken_session_of_null_is_none );
          ( "Wire.decode_taken_session of the node test's kv_after.json is the \
             refreshed session",
            `Quick,
            decode_taken_session_of_the_js_refresh );
        ] );
      ( "run_to_string",
        [
          ( "is the documented line",
            `Quick,
            run_to_string_is_the_documented_line );
          ( "is the line the job printed, for every run of the node test",
            `Quick,
            run_to_string_is_the_jobs_line );
          ( "contains no token, on the node test's runs",
            `Quick,
            run_to_string_contains_no_token );
        ] );
      ( "configuration",
        [
          ( "capacitor.config.ts's label, event and interval",
            `Quick,
            config_matches_the_constants );
          ("the job listens to every event", `Quick, job_listens_to_every_event);
        ] );
    ]
