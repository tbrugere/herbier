(* The rendered request is what Postgrest.Client.Make hands to its HTTP
   backend's [send]: [R = Rest.Make (H)] over the copied [Mock_http] is that
   backend here, as in test/postgrest's own suite. This file is the entry
   point: it also runs Test_synced's and Test_push_order's suites. *)

module Testable = Herbier_test_support.Testable
module Synced = Herbier_sync_core.Synced
module Rest = Herbier_sync_core.Net.Rest
module Outbox = Herbier_store.Outbox
module F = Sync_fixtures
module R = Sync_fixtures.R
module Ids = Herbier_domain.Ids
module Plant = Herbier_domain.Plant
module Observation = Herbier_domain.Observation
module Photo = Herbier_domain.Photo
module Tag = Herbier_domain.Tag
module Reference = Herbier_domain.Reference
module Source = Reference.Source
module Status = Reference.Status
module Client = Postgrest.Client
module Col = Postgrest.Col
module Input = Postgrest.Input
module Fixture = Herbier_test_support.Fixture
module Text = Herbier_test_support.Text

let t1 = F.time "2026-11-01T10:00:00Z"

(* ---------- minimal rows, one per synced table ---------- *)

let plant_min = F.plant ~at:t1 1 "Digitale"
let tag_min = F.tag ~at:t1 1 "Vivace"
let observation_min = F.observation ~at:t1 1
let photo_min = F.photo ~at:t1 ~observation:1 1
let plant_tag_min = F.plant_tag ~at:t1 ~plant:1 ~tag:1 1
let plant_ref_min = F.plant_ref ~at:t1 ~plant:1 1
let reference_min = F.reference ~at:t1 ~plant:1 1

type minimal = Minimal : ('table, 'row) Synced.t * 'row -> minimal

let minimal_rows =
  [
    Minimal (Synced.plants, plant_min);
    Minimal (Synced.tags, tag_min);
    Minimal (Synced.observations, observation_min);
    Minimal (Synced.photos, photo_min);
    Minimal (Synced.plant_tags, plant_tag_min);
    Minimal (Synced.plant_refs, plant_ref_min);
    Minimal (Synced.reference, reference_min);
  ]

(* ---------- header checks ---------- *)

let check_headers_exact name expected_pairs (r : Mock_http.request) =
  let lower = String.lowercase_ascii in
  Alcotest.(check (list string))
    (name ^ ": header names, exactly")
    (List.sort String.compare (List.map (fun (k, _) -> lower k) expected_pairs))
    (List.sort String.compare (List.map (fun (k, _) -> lower k) r.headers));
  List.iter
    (fun (k, v) ->
      match Mock_http.header k r with
      | Some v' -> Alcotest.(check string) (name ^ ": header " ^ k) v v'
      | None -> Alcotest.failf "%s: missing header %s" name k)
    expected_pairs

(* ---------- Rest.conn ---------- *)

let conn_base_url_and_headers () =
  let check_one ~supabase_url =
    let conn = Rest.conn ~supabase_url ~apikey:"K" ~token:"T" in
    Alcotest.(check string)
      (Printf.sprintf "base_url of %S" supabase_url)
      "http://127.0.0.1:54321/rest/v1"
      (Uri.to_string conn.base_url);
    Alcotest.(check (list (pair string string)))
      (Printf.sprintf "headers of %S" supabase_url)
      (List.sort compare [("Authorization", "Bearer T"); ("apikey", "K")])
      (List.sort compare (conn.headers ()))
  in
  check_one ~supabase_url:"http://127.0.0.1:54321";
  check_one ~supabase_url:"http://127.0.0.1:54321/"

(* ---------- classify_status ---------- *)

let status_class =
  Alcotest.testable Rest.pp_status_class Rest.equal_status_class

let classify_status_classes () =
  let check status expected =
    Alcotest.check status_class
      (Printf.sprintf "classify_status %d" status)
      expected
      (Rest.classify_status status)
  in
  check 540 Rest.Paused;
  check 401 Rest.Unauthorized;
  List.iter (fun s -> check s Rest.Transient) [408; 429; 500; 502; 503; 504];
  List.iter (fun s -> check s Rest.Rejected) [400; 403; 404; 406; 409; 422];
  (* The edges of the ranges. *)
  check 499 Rest.Rejected;
  check 539 Rest.Transient;
  check 541 Rest.Transient;
  (* rest.mli's fallback below 400; the client reports a status as an error
     only from 400 up, so the app never sees one. *)
  check 304 Rest.Transient

(* ---------- Upsert ---------- *)

let json = Testable.yojson

(* Bodies written out by hand: timestamps in whole seconds UTC (the
   library's encoding), ids as lowercase strings. *)
let str s = `String s

let plant_full : Plant.t =
  {
    id = F.plant_id 1;
    display_name = "Digitale";
    aliases = ["Digitale"; "Gant de Notre-Dame"];
    scientific_name = Some "Digitalis purpurea";
    authorship = Some "L.";
    gbif_key = Some 5414995;
    notes = "Vue au bord du chemin";
    notes_updated_at = Some t1;
    cover_photo_id = Some (F.photo_id 9);
    created_at = t1;
    updated_at = t1;
    deleted_at = Some t1;
  }

let plant_full_body : Yojson.Safe.t =
  `Assoc
    [
      ("id", str "01965d4e-0000-7000-8000-000000000001");
      ("display_name", str "Digitale");
      ("aliases", `List [str "Digitale"; str "Gant de Notre-Dame"]);
      ("scientific_name", str "Digitalis purpurea");
      ("authorship", str "L.");
      ("gbif_key", `Int 5414995);
      ("notes", str "Vue au bord du chemin");
      ("notes_updated_at", str "2026-11-01T10:00:00Z");
      ("cover_photo_id", str "01965d4e-0000-7000-8000-000000000009");
      ("created_at", str "2026-11-01T10:00:00Z");
      ("updated_at", str "2026-11-01T10:00:00Z");
      ("deleted_at", str "2026-11-01T10:00:00Z");
    ]

let reference_one : Reference.t =
  {
    id = F.reference_id 1;
    plant_id = F.plant_id 1;
    source = Source.Gbif;
    fetched_at = t1;
    payload = `Assoc [("species", `Assoc [("key", `Int 5414995)])];
    status = Status.Complete;
    created_at = t1;
    updated_at = t1;
    deleted_at = None;
  }

let reference_one_body : Yojson.Safe.t =
  `Assoc
    [
      ("id", str "01965d4e-0000-7000-8000-000000000001");
      ("plant_id", str "01965d4e-0000-7000-8000-000000000001");
      ("source", str "gbif");
      ("fetched_at", str "2026-11-01T10:00:00Z");
      ("payload", `Assoc [("species", `Assoc [("key", `Int 5414995)])]);
      ("status", str "complete");
      ("created_at", str "2026-11-01T10:00:00Z");
      ("updated_at", str "2026-11-01T10:00:00Z");
      ("deleted_at", `Null);
    ]

let upsert_headers =
  [
    ("Authorization", "Bearer T");
    ("apikey", "K");
    ("Prefer", "resolution=merge-duplicates,missing=default");
    ("Content-Type", "application/json");
  ]

let upsert_plant_every_field_set () =
  let p = plant_full in
  List.iter
    (fun status ->
      Mock_http.reset ();
      Mock_http.respond ~status (match status with 200 -> "[]" | _ -> "");
      (match R.upsert F.conn Synced.plants p with
      | Ok () -> ()
      | Error e ->
          Alcotest.failf "status %d: expected Ok, got %s" status
            (R.error_to_string e));
      let req = Mock_http.last () in
      Alcotest.(check string)
        "method" "POST"
        (Mock_http.string_of_meth req.meth);
      Alcotest.(check string)
        "target, no query string" "/rest/v1/plants"
        (Mock_http.decoded_target req.url);
      check_headers_exact "upsert plants" upsert_headers req;
      let body =
        match req.body with
        | Some b -> Yojson.Safe.from_string b
        | None -> Alcotest.fail "no body"
      in
      Alcotest.check json "body matches every column" plant_full_body body)
    [201; 200]

let upsert_reference_row () =
  let r = reference_one in
  Mock_http.reset ();
  Mock_http.respond ~status:201 "";
  (match R.upsert F.conn Synced.reference r with
  | Ok () -> ()
  | Error e -> Alcotest.failf "expected Ok, got %s" (R.error_to_string e));
  let req = Mock_http.last () in
  Alcotest.(check string) "method" "POST" (Mock_http.string_of_meth req.meth);
  Alcotest.(check string)
    "target, no query string" "/rest/v1/reference"
    (Mock_http.decoded_target req.url);
  check_headers_exact "upsert reference" upsert_headers req;
  let body =
    match req.body with
    | Some b -> Yojson.Safe.from_string b
    | None -> Alcotest.fail "no body"
  in
  Alcotest.check json "body matches every column, payload as an object"
    reference_one_body body

(* Read on first use, so that a missing catalog fails the tests that need
   it rather than the whole executable. *)
let catalog_tables = lazy (Support.Catalog.read ())

let catalog_columns name =
  List.sort String.compare
    (Support.Catalog.synced_columns
       (Support.Catalog.find name (Lazy.force catalog_tables)))

let every_table_upsert_shape () =
  Alcotest.(check (list string))
    "a minimal row per synced table"
    (List.sort String.compare
       (List.map (fun (Synced.Any t) -> Synced.name t) Synced.all))
    (List.sort String.compare
       (List.map (fun (Minimal (t, _)) -> Synced.name t) minimal_rows));
  List.iter
    (fun (Minimal (t, row)) ->
      Mock_http.reset ();
      Mock_http.respond ~status:201 "";
      let name = Synced.name t in
      (match R.upsert F.conn t row with
      | Ok () -> ()
      | Error e ->
          Alcotest.failf "%s: expected Ok, got %s" name (R.error_to_string e));
      let req = Mock_http.last () in
      Alcotest.(check string)
        (name ^ ": method") "POST"
        (Mock_http.string_of_meth req.meth);
      Alcotest.(check string)
        (name ^ ": target") ("/rest/v1/" ^ name)
        (Mock_http.decoded_target req.url);
      let body =
        match req.body with
        | Some b -> Yojson.Safe.from_string b
        | None -> Alcotest.failf "%s: no body" name
      in
      let keys =
        match body with
        | `Assoc kvs -> List.sort String.compare (List.map fst kvs)
        | j ->
            Alcotest.failf "%s: body is %s, not an object" name
              (Yojson.Safe.to_string j)
      in
      Alcotest.(check (list string))
        (name ^ ": body keys = catalog columns")
        (catalog_columns name) keys)
    minimal_rows

(* ---------- Select-since ---------- *)

let select_headers =
  [
    ("Authorization", "Bearer T");
    ("apikey", "K");
    ("Range-Unit", "items");
    ("Range", "0-499");
    ("Accept", "application/json");
    ("Prefer", "missing=default");
  ]

let plants_select_columns =
  "id,display_name,aliases,scientific_name,authorship,gbif_key,notes,notes_updated_at,cover_photo_id,created_at,updated_at,deleted_at"

(* A target is compared as its path and its query parameters as a
   set. The library adds parameters with [Uri.add_query_param'], which
   prepends, so the rendered order (order, select, then filters) is a
   rendering detail of the library, not part of the request's meaning
   (PostgREST reads parameters by name). *)
let split_target target =
  let path, qs =
    match String.index_opt target '?' with
    | None -> (target, "")
    | Some i ->
        ( String.sub target 0 i,
          String.sub target (i + 1) (String.length target - i - 1) )
  in
  let param seg =
    match String.index_opt seg '=' with
    | None -> (seg, "")
    | Some i ->
        (String.sub seg 0 i, String.sub seg (i + 1) (String.length seg - i - 1))
  in
  let params =
    match qs with "" -> [] | _ -> List.map param (String.split_on_char '&' qs)
  in
  (path, List.sort compare params)

let target_testable = Alcotest.(pair string (list (pair string string)))

let select_since_plants_no_filter () =
  Mock_http.reset ();
  Mock_http.respond ~status:200 "[]";
  (match R.select_since F.conn Synced.plants ~since:None ~page:0 with
  | Ok [] -> ()
  | Ok _ -> Alcotest.fail "expected []"
  | Error e -> Alcotest.failf "expected Ok, got %s" (R.error_to_string e));
  let req = Mock_http.last () in
  Alcotest.(check string) "method" "GET" (Mock_http.string_of_meth req.meth);
  Alcotest.check target_testable "target, since:None: path and parameters"
    ( "/rest/v1/plants",
      [("order", "updated_at,id"); ("select", plants_select_columns)] )
    (split_target (Mock_http.decoded_target req.url));
  check_headers_exact "select_since plants" select_headers req;
  Alcotest.(check (option string)) "no body" None req.body

let select_since_plants_with_since () =
  Mock_http.reset ();
  Mock_http.respond ~status:200 "[]";
  let since = F.time "2026-11-12T10:00:07.654321Z" in
  (match R.select_since F.conn Synced.plants ~since:(Some since) ~page:0 with
  | Ok [] -> ()
  | Ok _ -> Alcotest.fail "expected []"
  | Error e -> Alcotest.failf "expected Ok, got %s" (R.error_to_string e));
  Alcotest.check target_testable
    "target, since:Some: the filter's bound is since - 5 s in whole seconds"
    ( "/rest/v1/plants",
      [
        ("order", "updated_at,id");
        ("select", plants_select_columns);
        ("updated_at", "gt.2026-11-12T10:00:02Z");
      ] )
    (split_target (Mock_http.decoded_target (Mock_http.last ()).url))

(* The second page keeps the same since and filter and moves only the
   Range: paging from the last row's updated_at would not advance past a
   page of rows sharing one updated_at. *)
let select_since_plants_second_page () =
  Mock_http.reset ();
  Mock_http.respond ~status:200 "[]";
  let since = F.time "2026-11-12T10:00:07.654321Z" in
  (match R.select_since F.conn Synced.plants ~since:(Some since) ~page:1 with
  | Ok [] -> ()
  | Ok _ -> Alcotest.fail "expected []"
  | Error e -> Alcotest.failf "expected Ok, got %s" (R.error_to_string e));
  let req = Mock_http.last () in
  Alcotest.check target_testable "target: the same filter as page 0"
    ( "/rest/v1/plants",
      [
        ("order", "updated_at,id");
        ("select", plants_select_columns);
        ("updated_at", "gt.2026-11-12T10:00:02Z");
      ] )
    (split_target (Mock_http.decoded_target req.url));
  check_headers_exact "select_since plants, page 1"
    (List.map
       (function "Range", _ -> ("Range", "500-999") | kv -> kv)
       select_headers)
    req

let select_param target = List.assoc_opt "select" (snd (split_target target))

(* Every table: the request's shape, and the select= columns
   are exactly the catalog's non-server-only columns. *)
let every_table_select_since_shape () =
  List.iter
    (fun (Synced.Any t) ->
      Mock_http.reset ();
      Mock_http.respond ~status:200 "[]";
      let name = Synced.name t in
      (match R.select_since F.conn t ~since:None ~page:0 with
      | Ok _ -> ()
      | Error e ->
          Alcotest.failf "%s: expected Ok, got %s" name (R.error_to_string e));
      let target = Mock_http.decoded_target (Mock_http.last ()).url in
      let path, params = split_target target in
      Alcotest.(check string)
        (name ^ ": path is /rest/v1/<name>")
        ("/rest/v1/" ^ name) path;
      Alcotest.(check (list string))
        (name ^ ": parameters are order and select")
        ["order"; "select"] (List.map fst params);
      Alcotest.(check (option string))
        (name ^ ": order=updated_at,id")
        (Some "updated_at,id")
        (List.assoc_opt "order" params);
      let selected =
        match select_param target with
        | Some s -> List.sort String.compare (String.split_on_char ',' s)
        | None -> Alcotest.failf "%s: no select= in %s" name target
      in
      Alcotest.(check (list string))
        (name ^ ": select= columns = catalog columns")
        (catalog_columns name) selected)
    Synced.all

(* ---------- Errors ---------- *)

(* Compared by constructor and arguments (plain data: strings, ints and
   constant variants); printed with error_to_string, whose text is checked
   below. *)
let rest_error =
  Alcotest.testable
    (fun f e -> Format.pp_print_string f (R.error_to_string e))
    (fun (a : R.error) b -> a = b)

let error_to_string_per_constructor () =
  List.iter
    (fun (e, expected) ->
      Alcotest.(check string) expected expected (R.error_to_string e))
    [
      (R.Offline "boom", "offline: boom");
      (R.Paused, "paused (540)");
      (R.Unauthorized, "unauthorized (401)");
      (R.Transient 503, "transient (503)");
      (R.Rejected 409, "rejected (409)");
      (R.Bad_response Client.ExpectedArray, "bad response: expected an array");
      (R.Bad_response (Client.JsonError "eof"), "bad response: not JSON: eof");
      ( R.Bad_response (Client.RowError (2, `Missing)),
        "bad response: row 2: missing column" );
    ]

(* The recorded bodies are what PostgREST answered; the library keeps only
   the status of an error, so they document the case rather than steer it. *)
let upsert_errors () =
  let case what ~status ~body expected =
    Mock_http.reset ();
    (match status with
    | None -> Mock_http.fail_with "boom"
    | Some s -> Mock_http.respond ~status:s body);
    Alcotest.(check (result unit rest_error))
      what (Error expected)
      (R.upsert F.conn Synced.observations observation_min)
  in
  case "offline: the backend's error wrapped" ~status:None ~body:""
    (R.Offline "boom");
  case "540: Paused" ~status:(Some 540) ~body:"" R.Paused;
  case "401 bad jwt: Unauthorized" ~status:(Some 401)
    ~body:(Fixture.read "sync_upsert_plants_bad_jwt_401.json")
    R.Unauthorized;
  case "409 fk violation: Rejected 409" ~status:(Some 409)
    ~body:(Fixture.read "sync_upsert_observations_fk_409.json")
    (R.Rejected 409);
  case "400 check violation: Rejected 400" ~status:(Some 400)
    ~body:(Fixture.read "sync_upsert_observations_check_400.json")
    (R.Rejected 400);
  case "anon (401 as recorded): its class" ~status:(Some 401)
    ~body:(Fixture.read "sync_upsert_plants_anon_401.json")
    R.Unauthorized;
  case "503: Transient 503" ~status:(Some 503) ~body:"" (R.Transient 503)

let select_decode_errors () =
  let run body =
    Mock_http.reset ();
    Mock_http.respond ~status:200 body;
    R.select_since F.conn Synced.tags ~since:None ~page:0
  in
  (match run "{}" with
  | Error (R.Bad_response Client.ExpectedArray) -> ()
  | Ok _ -> Alcotest.fail "200 {}: expected Error"
  | Error e ->
      Alcotest.failf "200 {}: expected Bad_response ExpectedArray, got %s"
        (R.error_to_string e));
  (match run "not json" with
  | Error (R.Bad_response (Client.JsonError _)) -> ()
  | Ok _ -> Alcotest.fail "not json: expected Error"
  | Error e ->
      Alcotest.failf "not json: expected Bad_response (JsonError _), got %s"
        (R.error_to_string e));
  match run {|[{"id":"x"}]|} with
  | Error (R.Bad_response (Client.RowError (0, _))) -> ()
  | Ok _ -> Alcotest.fail {|[{"id":"x"}]: expected Error|}
  | Error e ->
      Alcotest.failf
        {|[{"id":"x"}]: expected Bad_response (RowError (0, _)), got %s|}
        (R.error_to_string e)

let error_to_string_never_contains_the_token () =
  let marker = "SECRET-TOKEN-MARKER" in
  let conn =
    Rest.conn ~supabase_url:"http://127.0.0.1:54321" ~apikey:"K" ~token:marker
  in
  let error_of ~status ~body =
    Mock_http.reset ();
    Mock_http.respond ~status body;
    match R.upsert conn Synced.plants plant_min with
    | Error e -> e
    | Ok () -> Alcotest.fail "expected an error"
  in
  let errors =
    [
      error_of ~status:401
        ~body:(Fixture.read "sync_upsert_plants_bad_jwt_401.json");
      error_of ~status:409
        ~body:(Fixture.read "sync_upsert_observations_fk_409.json");
      error_of ~status:503 ~body:"";
      error_of ~status:540 ~body:"";
    ]
  in
  List.iter
    (fun e ->
      Alcotest.(check bool)
        (Printf.sprintf "%s does not contain the token" (R.error_to_string e))
        false
        (Text.contains ~sub:marker (R.error_to_string e)))
    errors

(* ---------- Decoding recorded answers ---------- *)

(* [expected_updated_at] is the fixture's server value, written out; its
   microseconds are also checked as a span, so that a decoder truncating
   them fails whatever Ptime's parser does. The fixture's keys are the
   catalog's columns, so a column added or dropped since the recording
   fails here and points at scripts/record-sync-fixtures.sh. *)
let decode_one (type table row) name (t : (table, row) Synced.t)
    ~(equal : row -> row -> bool) ~(updated_at : row -> Ptime.t)
    ~expected_updated_at ~micro ~(with_updated_at : Ptime.t -> row) =
  let text = Fixture.read (Printf.sprintf "sync_select_%s_200.json" name) in
  (match Yojson.Safe.from_string text with
  | `List [`Assoc kvs] ->
      Alcotest.(check (list string))
        (name ^ ": the fixture's keys are the catalog's columns")
        (catalog_columns name)
        (List.sort String.compare (List.map fst kvs))
  | _ -> Alcotest.failf "%s: the fixture is not one object in an array" name);
  Mock_http.reset ();
  Mock_http.respond ~status:200 text;
  match R.select_since F.conn t ~since:None ~page:0 with
  | Error e ->
      Alcotest.failf "%s: expected Ok, got %s" name (R.error_to_string e)
  | Ok [row] ->
      Alcotest.(check bool)
        (name ^ ": updated_at keeps its microseconds")
        true
        (Ptime.Span.equal
           (Ptime.frac_s (updated_at row))
           (Ptime.Span.v (0, Int64.mul (Int64.of_int micro) 1_000_000L)));
      Alcotest.(check bool)
        (name ^ ": every field matches")
        true
        (equal (with_updated_at (F.time expected_updated_at)) row)
  | Ok rows ->
      Alcotest.failf "%s: expected one row, got %d" name (List.length rows)

let sent_reference_payload : Yojson.Safe.t =
  `Assoc
    [
      ( "vernacular",
        `List
          [
            `Assoc
              [("name", `String "Digitale pourpre"); ("lang", `String "fra")];
          ] );
      ( "species",
        `Assoc
          [
            ("rank", `String "SPECIES");
            ("key", `Int 5414995);
            ("canonicalName", `String "Digitalis purpurea");
          ] );
    ]

let decoding_recorded_answers () =
  decode_one "plants" Synced.plants ~equal:Plant.equal
    ~updated_at:(fun (p : Plant.t) -> p.updated_at)
    ~expected_updated_at:"2026-11-12T12:25:29.680827Z" ~micro:680827
    ~with_updated_at:(fun updated_at : Plant.t ->
      {
        id = F.plant_id 1;
        display_name = "Digitale pourpre";
        aliases = ["Digitale"; "Gant de Notre-Dame"];
        scientific_name = Some "Digitalis purpurea";
        authorship = Some "L.";
        gbif_key = Some 5414995;
        notes = "Mi-ombre";
        notes_updated_at = Some (F.time "2026-11-12T09:07:00Z");
        cover_photo_id = Some (F.photo_id 4);
        created_at = F.time "2026-11-12T09:00:00Z";
        updated_at;
        deleted_at = None;
      });
  decode_one "tags" Synced.tags ~equal:Tag.equal
    ~updated_at:(fun (t : Tag.t) -> t.updated_at)
    ~expected_updated_at:"2026-11-12T12:25:29.323122Z" ~micro:323122
    ~with_updated_at:(fun updated_at : Tag.t ->
      {
        id = F.tag_id 2;
        name = "Lisière";
        created_at = F.time "2026-11-12T09:01:00Z";
        updated_at;
        deleted_at = None;
      });
  decode_one "observations" Synced.observations ~equal:Observation.equal
    ~updated_at:(fun (o : Observation.t) -> o.updated_at)
    ~expected_updated_at:"2026-11-12T12:25:29.355985Z" ~micro:355985
    ~with_updated_at:(fun updated_at : Observation.t ->
      {
        id = F.observation_id 3;
        plant_id = Some (F.plant_id 1);
        at = F.time "2026-11-12T08:45:00Z";
        position =
          Some {Observation.lat = 45.5; lon = 3.25; accuracy_m = Some 12.5};
        place_label = Some "Bois";
        place_derived = None;
        note = Some "Fleurs ouvertes";
        created_at = F.time "2026-11-12T09:02:00Z";
        updated_at;
        deleted_at = None;
      });
  decode_one "photos" Synced.photos ~equal:Photo.equal
    ~updated_at:(fun (p : Photo.t) -> p.updated_at)
    ~expected_updated_at:"2026-11-12T12:25:29.508002Z" ~micro:508002
    ~with_updated_at:(fun updated_at : Photo.t ->
      {
        id = F.photo_id 4;
        observation_id = F.observation_id 3;
        taken_at = F.time "2026-11-12T08:46:00Z";
        width = 1600;
        height = 1200;
        sha256 =
          "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08";
        preview_path = "previews/" ^ F.uuid 4 ^ ".jpg";
        preview_bucket_key = None;
        original_target = Photo.Original_target.Drive;
        drive_file_id = None;
        upload_state = Photo.Upload_state.Pending;
        created_at = F.time "2026-11-12T09:03:00Z";
        updated_at;
        deleted_at = None;
      });
  decode_one "plant_tags" Synced.plant_tags ~equal:Tag.Plant_tag.equal
    ~updated_at:(fun (t : Tag.Plant_tag.t) -> t.updated_at)
    ~expected_updated_at:"2026-11-12T12:25:29.542462Z" ~micro:542462
    ~with_updated_at:(fun updated_at : Tag.Plant_tag.t ->
      {
        id = F.plant_tag_id 5;
        plant_id = F.plant_id 1;
        tag_id = F.tag_id 2;
        created_at = F.time "2026-11-12T09:04:00Z";
        updated_at;
        deleted_at = None;
      });
  decode_one "plant_refs" Synced.plant_refs ~equal:Reference.Plant_ref.equal
    ~updated_at:(fun (r : Reference.Plant_ref.t) -> r.updated_at)
    ~expected_updated_at:"2026-11-12T12:25:29.615646Z" ~micro:615646
    ~with_updated_at:(fun updated_at : Reference.Plant_ref.t ->
      {
        id = F.plant_ref_id 6;
        plant_id = F.plant_id 1;
        source = Source.Gbif;
        external_id = "5414995";
        url = "https://www.gbif.org/species/5414995";
        created_at = F.time "2026-11-12T09:05:00Z";
        updated_at;
        deleted_at = None;
      });
  decode_one "reference" Synced.reference ~equal:Reference.equal
    ~updated_at:(fun (r : Reference.t) -> r.updated_at)
    ~expected_updated_at:"2026-11-12T12:25:29.652692Z" ~micro:652692
    ~with_updated_at:(fun updated_at : Reference.t ->
      {
        id = F.reference_id 7;
        plant_id = F.plant_id 1;
        source = Source.Gbif;
        fetched_at = F.time "2026-11-12T09:06:00Z";
        payload = sent_reference_payload;
        status = Status.Complete;
        created_at = F.time "2026-11-12T09:06:00Z";
        updated_at;
        deleted_at = None;
      })

let reference_payload_is_structural_not_textual () =
  Mock_http.reset ();
  Mock_http.respond ~status:200 (Fixture.read "sync_select_reference_200.json");
  match R.select_since F.conn Synced.reference ~since:None ~page:0 with
  | Ok [(r : Reference.t)] ->
      Alcotest.check json "Yojson.Safe.equal to the sent object"
        sent_reference_payload r.payload;
      Alcotest.(check bool)
        "to_string differs (jsonb reordered the keys)" false
        (String.equal
           (Yojson.Safe.to_string r.payload)
           (Yojson.Safe.to_string sent_reference_payload))
  | Ok rows -> Alcotest.failf "expected one row, got %d" (List.length rows)
  | Error e -> Alcotest.failf "expected Ok, got %s" (R.error_to_string e)

(* ---------- Payload round trip ---------- *)

(* The outbox keeps a payload as JSON text in SQLite: the round trip goes
   through the text too. *)
let round_trip (type table row) name (t : (table, row) Synced.t) (row : row) =
  let payload1 = Input.to_json (Synced.input t row) in
  let stored = Yojson.Safe.from_string (Yojson.Safe.to_string payload1) in
  match Synced.decode_payload t stored with
  | Error e ->
      Alcotest.failf "%s: decode_payload: %s" name
        (Herbier_store.Codec.row_error_to_string e)
  | Ok row' ->
      let payload2 = Input.to_json (Synced.input t row') in
      Alcotest.check json
        (name ^ ": round-trip payload is structurally equal")
        payload1 payload2

let observation_full : Observation.t =
  {
    observation_min with
    plant_id = Some (F.plant_id 1);
    position = Some {Observation.lat = 45.5; lon = 3.25; accuracy_m = Some 12.5};
    place_label = Some "Bois";
    note = Some "Fleurs ouvertes";
    deleted_at = Some t1;
  }

let reference_full : Reference.t =
  {reference_min with payload = sent_reference_payload; deleted_at = Some t1}

let payload_round_trip () =
  round_trip "plants" Synced.plants plant_min;
  round_trip "tags" Synced.tags tag_min;
  round_trip "observations" Synced.observations observation_min;
  round_trip "photos" Synced.photos photo_min;
  round_trip "plant_tags" Synced.plant_tags plant_tag_min;
  round_trip "plant_refs" Synced.plant_refs plant_ref_min;
  round_trip "reference" Synced.reference reference_min;
  round_trip "plants, every field set" Synced.plants plant_full;
  round_trip "observations, every field set" Synced.observations
    observation_full;
  round_trip "reference, a nested payload" Synced.reference reference_full

(* ---------- An outbox entry: decode_entry, then upsert ---------- *)

let entry_error =
  Alcotest.testable
    (fun f e -> Format.pp_print_string f (Synced.entry_error_to_string e))
    (fun (a : Synced.entry_error) b -> a = b)

let decode_entry_error ~table_name payload =
  match Synced.decode_entry ~table_name payload with
  | Ok (_ : Synced.entry) -> None
  | Error e -> Some e

let push_sends_a_structurally_equal_body () =
  Mock_http.reset ();
  Mock_http.respond ~status:201 "";
  let payload = Input.to_json (Synced.input Synced.plants plant_min) in
  (match Synced.decode_entry ~table_name:"plants" payload with
  | Error e ->
      Alcotest.failf "expected a plants entry, got %s"
        (Synced.entry_error_to_string e)
  | Ok (Entry (t, row)) -> (
      match R.upsert F.conn t row with
      | Ok () -> ()
      | Error e -> Alcotest.failf "expected Ok, got %s" (R.error_to_string e)));
  let body =
    match (Mock_http.last ()).body with
    | Some b -> Yojson.Safe.from_string b
    | None -> Alcotest.fail "no body"
  in
  Alcotest.check json "the sent body is structurally equal to the payload"
    payload body

let decode_entry_unknown_table () =
  Alcotest.(check (option entry_error))
    "Unknown_table" (Some (Unknown_table "outbox"))
    (decode_entry_error ~table_name:"outbox" (`Assoc []))

let plant_min_payload_with f =
  match Input.to_json (Synced.input Synced.plants plant_min) with
  | `Assoc kvs -> `Assoc (f kvs)
  | _ -> Alcotest.fail "a plant payload is an object"

let expect_bad_payload row_error payload =
  Alcotest.(check (option entry_error))
    "Bad_payload"
    (Some (Bad_payload ("plants", row_error)))
    (decode_entry_error ~table_name:"plants" payload)

(* Only display_name is missing, so the decode can fail on nothing else. *)
let decode_entry_missing_display_name_is_bad_payload () =
  expect_bad_payload `Missing
    (plant_min_payload_with (List.remove_assoc "display_name"))

(* An integer literal beyond a native int: the decoder raises Failure, and
   decode_entry must turn it into Bad_payload rather than let it escape. *)
let decode_entry_oversized_integer_is_bad_payload () =
  let payload =
    plant_min_payload_with (fun kvs ->
        ("gbif_key", `Intlit "99999999999999999999999")
        :: List.remove_assoc "gbif_key" kvs)
  in
  (match Synced.decode_payload Synced.plants payload with
  | Error `WrongType -> ()
  | Error e ->
      Alcotest.failf "expected WrongType, got %s"
        (Herbier_store.Codec.row_error_to_string e)
  | Ok _ -> Alcotest.fail "expected Error");
  expect_bad_payload `WrongType payload

(* ---------- Synced.decide ---------- *)

let decision =
  Alcotest.testable Herbier_domain.Merge.pp_decision
    Herbier_domain.Merge.equal_decision

let synced_decide_uses_the_table_s_equal () =
  let local =
    {
      reference_min with
      payload =
        `Assoc
          [
            ( "species",
              `Assoc [("key", `Int 5414995); ("rank", `String "SPECIES")] );
            ("lang", `String "fr");
          ];
    }
  in
  let reordered =
    {
      local with
      payload =
        `Assoc
          [
            ("lang", `String "fr");
            ( "species",
              `Assoc [("rank", `String "SPECIES"); ("key", `Int 5414995)] );
          ];
    }
  in
  let changed =
    {
      local with
      payload =
        `Assoc
          [
            ( "species",
              `Assoc [("key", `Int 5414996); ("rank", `String "SPECIES")] );
            ("lang", `String "fr");
          ];
    }
  in
  let decide = Synced.decide Synced.reference ~pending:false in
  Alcotest.check decision "reference, keys reordered: Unchanged"
    Herbier_domain.Merge.Unchanged
    (decide ~local:(Some local) reordered);
  Alcotest.check decision "reference, a nested value changed: Replace"
    Herbier_domain.Merge.Replace
    (decide ~local:(Some local) changed);
  Alcotest.check decision "plants, no local row: Insert"
    Herbier_domain.Merge.Insert
    (Synced.decide Synced.plants ~pending:false ~local:None plant_min)

let tests =
  [
    ( "Rest.conn: base_url and headers, with and without a trailing slash",
      `Quick,
      conn_base_url_and_headers );
    ( "classify_status: 540, 401, transient and rejected classes, range edges",
      `Quick,
      classify_status_classes );
    ( "error_to_string: the text of each constructor",
      `Quick,
      error_to_string_per_constructor );
    ( "Synced.decide: the table's equal (reference payload as a structure)",
      `Quick,
      synced_decide_uses_the_table_s_equal );
    ( "upsert: a plant with every optional field set, status 201 and 200",
      `Quick,
      upsert_plant_every_field_set );
    ( "upsert: a reference row, payload sent as an object",
      `Quick,
      upsert_reference_row );
    ( "upsert: every table, method/target/body-keys",
      `Quick,
      every_table_upsert_shape );
    ( "select_since: plants, since:None, the literal request",
      `Quick,
      select_since_plants_no_filter );
    ( "select_since: plants, since:Some, the updated_at filter is since - 5 s",
      `Quick,
      select_since_plants_with_since );
    ( "select_since: page 1 asks Range 500-999 with the same filter",
      `Quick,
      select_since_plants_second_page );
    ( "select_since: every table's shape, and its select= columns against the \
       catalog",
      `Quick,
      every_table_select_since_shape );
    ( "upsert errors: offline, paused, unauthorized, rejected, transient",
      `Quick,
      upsert_errors );
    ( "select errors: a non-array body, invalid JSON, a row that fails to decode",
      `Quick,
      select_decode_errors );
    ( "error_to_string never contains the access token",
      `Quick,
      error_to_string_never_contains_the_token );
    ( "decoding recorded answers: every table's fixture decodes to what was sent",
      `Quick,
      decoding_recorded_answers );
    ( "reference payload: structural equality, not textual (jsonb reorder)",
      `Quick,
      reference_payload_is_structural_not_textual );
    ( "payload round trip: decode_payload (Input.to_json (Synced.input t v)) \
       re-encodes the same",
      `Quick,
      payload_round_trip );
    ( "push: an outbox payload, decoded and upserted, sends a structurally \
       equal body",
      `Quick,
      push_sends_a_structurally_equal_body );
    ( "decode_entry: an unknown table is Unknown_table",
      `Quick,
      decode_entry_unknown_table );
    ( "decode_entry: a plants payload missing display_name is Bad_payload",
      `Quick,
      decode_entry_missing_display_name_is_bad_payload );
    ( "decode_entry: an integer literal beyond int is Bad_payload",
      `Quick,
      decode_entry_oversized_integer_is_bad_payload );
  ]

let () =
  Alcotest.run "sync rest"
    [
      ("Synced", Test_synced.tests);
      ( "Rest: conn, status classes, rendered requests, errors, decoding, push",
        tests );
      ("Outbox ordering through push", Test_push_order.tests);
    ]
