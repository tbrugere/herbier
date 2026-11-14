(* Native checks of app/store/uploads.ml (the device-only [uploads] table,
   migration 5) through the sqlite3 CLI, exactly as test_commune_packs.ml
   checks Commune_packs: Cli.write_ok runs each statement as [Db.write] does
   on the device (no transaction, no outbox entry: [uploads] is not synced).
   Photos.set_upload is checked here too (through Cli.edit_ok, as
   test_outbox.ml checks every per-table edit). *)

module Schema = Herbier_store.Schema
module Uploads = Herbier_store.Uploads
module Outbox = Herbier_store.Outbox
module Observations = Herbier_store.Observations
module Photos = Herbier_store.Photos
module Input = Postgrest.Input
module Ids = Herbier_domain.Ids
module Observation = Herbier_domain.Observation
module Photo = Herbier_domain.Photo
module Value = Herbier_test_support.Value
module Cli = Sqlite_cli
module Text = Herbier_test_support.Text

(* ---------- fixtures ---------- *)

let time = Value.time
let uuid = Value.uuid4
let id_of what of_string n = Value.id what of_string (uuid n)
let photo_id = id_of "photo id" Ids.Photo_id.of_string
let observation_id = id_of "observation id" Ids.Observation_id.of_string
let t0 = time "2026-11-12T10:00:00Z"
let t1 = time "2026-11-12T11:30:05.5+01:00"
let t2 = time "2026-11-12T12:00:00Z"
let fk_on = "pragma foreign_keys = on;\n"

let observation n at : Observation.t =
  {
    id = observation_id n;
    plant_id = None;
    at;
    position = None;
    place_label = None;
    place_derived = None;
    note = None;
    created_at = t0;
    updated_at = t0;
    deleted_at = None;
  }

let photo ~observation:obs n taken_at : Photo.t =
  {
    id = photo_id n;
    observation_id = observation_id obs;
    taken_at;
    width = 1024;
    height = 768;
    sha256 = String.make 64 'a';
    preview_path = Printf.sprintf "previews/%d.webp" n;
    preview_bucket_key = None;
    original_target = Photo.Original_target.Drive;
    drive_file_id = None;
    upload_state = Photo.Upload_state.Pending;
    created_at = t0;
    updated_at = t0;
    deleted_at = None;
  }

(* Seeds an observation and one photo of it, bypassing the outbox (as a pull
   or Dev_seed would), so [uploads]' foreign key to [photos] is satisfied. *)
let seeded_db photo_ns =
  let db = Cli.migrated_db () in
  let (_ : int) =
    Cli.write_ok "seed observation" db
      (Outbox.bare_stmt
         (Outbox.without_entry (Observations.upsert (observation 0x31 t0))))
  in
  List.iter
    (fun n ->
      let (_ : int) =
        Cli.write_ok "seed photo" db
          (Outbox.bare_stmt
             (Outbox.without_entry
                (Photos.upsert (photo ~observation:0x31 n t0))))
      in
      ())
    photo_ns;
  db

let row ?(path = "originals/x") ?(mime = "image/jpeg") ?(size_bytes = 12_345)
    ?session ?(attempts = 0) ?(last_error = None) ?(created_at = t0) id :
    Uploads.t =
  {
    photo_id = id;
    path;
    mime;
    size_bytes;
    session;
    attempts;
    last_error;
    created_at;
  }

let session ?(created_at = t0) url : Uploads.session = {url; created_at}

(* ---------- testables ---------- *)

let session_json (s : Uploads.session) =
  `Assoc
    [
      ("url", `String s.url);
      ("created_at", `String (Ptime.to_rfc3339 ~tz_offset_s:0 s.created_at));
    ]

let row_json (r : Uploads.t) =
  `Assoc
    [
      ("photo_id", `String (Ids.Photo_id.to_string r.photo_id));
      ("path", `String r.path);
      ("mime", `String r.mime);
      ("size_bytes", `Int r.size_bytes);
      ( "session",
        match r.session with None -> `Null | Some s -> session_json s );
      ("attempts", `Int r.attempts);
      ( "last_error",
        match r.last_error with None -> `Null | Some e -> `String e );
      ("created_at", `String (Ptime.to_rfc3339 ~tz_offset_s:0 r.created_at));
    ]

let rows_json l = `List (List.map row_json l)

let check_rows what expected actual =
  Alcotest.(check Cli.yojson) what (rows_json expected) (rows_json actual)

(* ---------- migration 5 ---------- *)

(* Migration 5 alone on a v4 database, as test_commune_packs.ml applies
   migration 4: not Cli.migrate, which would also apply the later ones. *)
let migration_five_from_v4 () =
  let db = Cli.fresh_db () in
  let m5 =
    match Schema.migrations with
    | m1 :: m2 :: m3 :: m4 :: m5 :: _ ->
        Cli.apply_migrations db [m1; m2; m3; m4];
        m5
    | _ -> Alcotest.fail "need at least five migrations"
  in
  Alcotest.(check int)
    "after migrations 1-4, user_version is 4" 4 (Cli.user_version db);
  Alcotest.(check int)
    "uploads does not exist yet" 0
    (Cli.count db
       "select count(*) as n from sqlite_master where type = 'table' and name \
        = 'uploads';\n");
  (match Schema.pending ~current:4 with
  | Ok (m :: _) ->
      Alcotest.(check int)
        "pending ~current:4 starts with migration 5" 5 m.version
  | Ok [] -> Alcotest.fail "expected at least migration 5 pending"
  | Error (Schema.Unknown_version _) ->
      Alcotest.fail "expected Ok (migration 5 :: _)");
  Alcotest.(check int) "migration 5's own version is 5" 5 m5.version;
  Cli.apply_migrations db [m5];
  Alcotest.(check int)
    "user_version after migrating is 5" 5 (Cli.user_version db);
  Alcotest.(check (list string))
    "uploads columns"
    (List.sort String.compare
       [
         "photo_id";
         "path";
         "mime";
         "size_bytes";
         "session_url";
         "session_created_at";
         "attempts";
         "last_error";
         "created_at";
       ])
    (Cli.column_names db "uploads")

(* ---------- put, all, find ---------- *)

let put_then_find_round_trips_with_and_without_session () =
  let db = seeded_db [0x1; 0x2] in
  let without = row (photo_id 0x1) in
  let with_session =
    row ~session:(session "https://upload.test/s1") (photo_id 0x2)
  in
  let (_ : int) = Cli.write_ok "put without session" db (Uploads.put without) in
  let (_ : int) =
    Cli.write_ok "put with session" db (Uploads.put with_session)
  in
  (match Cli.find db (Uploads.find (photo_id 0x1)) with
  | Some r ->
      Alcotest.(check Cli.yojson)
        "without session" (row_json without) (row_json r)
  | None -> Alcotest.fail "expected a row for photo 0x1");
  match Cli.find db (Uploads.find (photo_id 0x2)) with
  | Some r ->
      Alcotest.(check Cli.yojson)
        "with session" (row_json with_session) (row_json r)
  | None -> Alcotest.fail "expected a row for photo 0x2"

let put_again_updates_in_place () =
  let db = seeded_db [0x1] in
  let v1 = row (photo_id 0x1) in
  let v2 =
    row ~attempts:1 ~last_error:(Some "HTTP 503")
      ~session:(session "https://upload.test/s2")
      (photo_id 0x1)
  in
  let (_ : int) = Cli.write_ok "put v1" db (Uploads.put v1) in
  let (_ : int) = Cli.write_ok "put v2 (same photo_id)" db (Uploads.put v2) in
  check_rows "one row, the second's values" [v2] (Cli.all db Uploads.all)

let all_orders_by_created_at_then_photo_id () =
  let db = seeded_db [0x1; 0x2; 0x3] in
  (* 0x1 and 0x3 share t0: photo_id breaks the tie (0x1 before 0x3); 0x2 is
     created later (t1) and so comes last. Put in another order to prove the
     ordering is not insertion order. *)
  let r3 = row ~created_at:t0 (photo_id 0x3) in
  let r1 = row ~created_at:t0 (photo_id 0x1) in
  let r2 = row ~created_at:t1 (photo_id 0x2) in
  List.iter
    (fun r -> ignore (Cli.write_ok "seed" db (Uploads.put r) : int))
    [r2; r3; r1];
  check_rows "0x1, 0x3 (same created_at, by photo_id), then 0x2 (later)"
    [r1; r3; r2] (Cli.all db Uploads.all)

let find_absent_is_none () =
  let db = seeded_db [0x1] in
  let (_ : int) = Cli.write_ok "put" db (Uploads.put (row (photo_id 0x1))) in
  Alcotest.(check bool)
    "0x2 is absent" true
    (Option.is_none (Cli.find db (Uploads.find (photo_id 0x2))))

(* ---------- remove ---------- *)

let remove_once_then_noop () =
  let db = seeded_db [0x1] in
  let (_ : int) = Cli.write_ok "put" db (Uploads.put (row (photo_id 0x1))) in
  Alcotest.(check int)
    "first remove: 1 change" 1
    (Cli.write_ok "remove" db (Uploads.remove (photo_id 0x1)));
  Alcotest.(check int)
    "second remove: 0 changes" 0
    (Cli.write_ok "remove again" db (Uploads.remove (photo_id 0x1)));
  check_rows "no row left" [] (Cli.all db Uploads.all)

(* ---------- constraints ---------- *)

let insert_sql ~photo_id ?(path = "'originals/x'") ?(mime = "'image/jpeg'")
    ?(size_bytes = "12345") ?(session_url = "NULL")
    ?(session_created_at = "NULL") ?(attempts = "0") ?(last_error = "NULL")
    ?(created_at = "'2026-11-12T10:00:00.000000Z'") () =
  Printf.sprintf
    "insert into uploads (photo_id, path, mime, size_bytes, session_url, \
     session_created_at, attempts, last_error, created_at) values ('%s', %s, \
     %s, %s, %s, %s, %s, %s, %s);\n"
    photo_id path mime size_bytes session_url session_created_at attempts
    last_error created_at

let rejected what ~because db sql =
  match Cli.sqlite db (fk_on ^ sql) with
  | Ok out -> Alcotest.failf "%s should be rejected, got %s" what out
  | Error e -> (
      match Text.contains ~sub:because e with
      | true -> ()
      | false ->
          Alcotest.failf "%s should be rejected for %S, got %s" what because e)

let negative_size_bytes_rejected () =
  let db = seeded_db [0x1] in
  rejected "size_bytes = -1" ~because:"CHECK constraint failed" db
    (insert_sql ~photo_id:(uuid 0x1) ~size_bytes:"-1" ())

let session_url_without_created_at_rejected () =
  let db = seeded_db [0x1] in
  rejected "session_url set with session_created_at null"
    ~because:"CHECK constraint failed" db
    (insert_sql ~photo_id:(uuid 0x1) ~session_url:"'https://upload.test/s'" ())

let created_at_without_session_url_rejected () =
  let db = seeded_db [0x1] in
  rejected "session_created_at set with session_url null"
    ~because:"CHECK constraint failed" db
    (insert_sql ~photo_id:(uuid 0x1)
       ~session_created_at:"'2026-11-12T10:00:00.000000Z'" ())

let negative_attempts_rejected () =
  let db = seeded_db [0x1] in
  rejected "attempts = -1" ~because:"CHECK constraint failed" db
    (insert_sql ~photo_id:(uuid 0x1) ~attempts:"-1" ())

let unknown_photo_rejected () =
  let db = Cli.migrated_db () in
  rejected "an upload row for a photo that does not exist"
    ~because:"FOREIGN KEY constraint failed" db
    (insert_sql ~photo_id:(uuid 0x99) ())

let photo_delete_cascades () =
  let db = seeded_db [0x1] in
  let (_ : int) =
    Cli.write_ok "seed upload" db (Uploads.put (row (photo_id 0x1)))
  in
  Cli.exec_ok "delete the photo" db
    (fk_on ^ Printf.sprintf "delete from photos where id = '%s';\n" (uuid 0x1));
  Alcotest.(check int)
    "the upload row went with its photo" 0
    (List.length (Cli.rows db "select photo_id from uploads;\n"))

(* ---------- not synced ---------- *)

let never_writes_outbox () =
  let db = seeded_db [0x1] in
  let before = Cli.outbox_count db in
  let (_ : int) = Cli.write_ok "put" db (Uploads.put (row (photo_id 0x1))) in
  let (_ : int) = Cli.write_ok "remove" db (Uploads.remove (photo_id 0x1)) in
  Alcotest.(check int) "outbox count unchanged" before (Cli.outbox_count db)

(* ---------- Photos.set_upload ---------- *)

(* A minimal stand-in for test_outbox.ml's [raw]/[outbox], local to this
   file: the outbox row as sqlite3 -json prints it, with its payload parsed. *)
let last_payload db =
  match List.rev (Cli.outbox db) with
  | r :: _ -> (
      let text = Cli.string_field "payload_json" r in
      match Yojson.Safe.from_string text with
      | j -> (Cli.string_field "table_name" r, Cli.string_field "row_id" r, j)
      | exception Yojson.Json_error m ->
          Alcotest.failf "payload_json %S is not JSON: %s" text m)
  | [] -> Alcotest.fail "the outbox is empty"

let check_edit what expected db edits =
  Alcotest.(check int) what expected (Cli.edit_ok what db edits)

let set_upload_on_a_live_photo_appends_an_entry () =
  let db = Cli.migrated_db () in
  let obs = observation 0x31 t0 in
  check_edit "seed observation" 1 db [Observations.upsert obs];
  let p = photo ~observation:0x31 0xf1 t0 in
  check_edit "seed photo" 1 db [Photos.upsert p];
  check_edit "set_upload on a live photo appends 1 entry" 1 db
    [
      Photos.set_upload p.id ~state:Photo.Upload_state.Uploaded
        ~drive_file_id:(Some "FILE1") ~at:t2;
    ];
  let updated =
    {
      p with
      upload_state = Photo.Upload_state.Uploaded;
      drive_file_id = Some "FILE1";
      updated_at = t2;
    }
  in
  (match Cli.find db (Photos.get p.id) with
  | Some r ->
      Alcotest.(check Cli.yojson)
        "the row has the new state, drive_file_id and updated_at"
        (Input.to_json (Photos.input updated))
        (Input.to_json (Photos.input r))
  | None -> Alcotest.fail "the photo row is gone");
  let table_name, row_id, payload = last_payload db in
  Alcotest.(check string) "table_name" "photos" table_name;
  Alcotest.(check string) "row_id" (Ids.Photo_id.to_string p.id) row_id;
  Alcotest.(check Cli.yojson)
    "payload carries upload_state, drive_file_id and updated_at"
    (Input.to_json (Photos.input updated))
    payload

let set_upload_on_a_soft_deleted_photo_is_a_noop () =
  let db = Cli.migrated_db () in
  let obs = observation 0x32 t0 in
  check_edit "seed observation" 1 db [Observations.upsert obs];
  let p = photo ~observation:0x32 0xf2 t0 in
  check_edit "seed photo" 1 db [Photos.upsert p];
  check_edit "soft delete" 1 db [Photos.soft_delete p.id ~at:t1];
  let before = Cli.outbox_count db in
  check_edit "set_upload on a soft-deleted photo appends nothing" 0 db
    [
      Photos.set_upload p.id ~state:Photo.Upload_state.Uploaded
        ~drive_file_id:(Some "FILE1") ~at:t2;
    ];
  Alcotest.(check int) "outbox count unchanged" before (Cli.outbox_count db)

let set_upload_failed_without_file_id () =
  let db = Cli.migrated_db () in
  let obs = observation 0x33 t0 in
  check_edit "seed observation" 1 db [Observations.upsert obs];
  let p = photo ~observation:0x33 0xf3 t0 in
  check_edit "seed photo" 1 db [Photos.upsert p];
  check_edit "set_upload Failed appends 1 entry" 1 db
    [
      Photos.set_upload p.id ~state:Photo.Upload_state.Failed
        ~drive_file_id:None ~at:t2;
    ];
  let updated =
    {
      p with
      upload_state = Photo.Upload_state.Failed;
      drive_file_id = None;
      updated_at = t2;
    }
  in
  let _, _, payload = last_payload db in
  Alcotest.(check Cli.yojson)
    "payload: upload_state failed, drive_file_id null"
    (Input.to_json (Photos.input updated))
    payload;
  match payload with
  | `Assoc fields ->
      Alcotest.(check Cli.yojson)
        "upload_state" (`String "failed")
        (Option.value (List.assoc_opt "upload_state" fields) ~default:`Null);
      Alcotest.(check Cli.yojson)
        "drive_file_id" `Null
        (Option.value
           (List.assoc_opt "drive_file_id" fields)
           ~default:(`String "absent"))
  | _ -> Alcotest.fail "payload is not an object"

let set_upload_on_an_unknown_photo_is_a_noop () =
  let db = Cli.migrated_db () in
  let before = Cli.outbox_count db in
  check_edit "set_upload on an unknown photo appends nothing" 0 db
    [
      Photos.set_upload (photo_id 0xf9) ~state:Photo.Upload_state.Failed
        ~drive_file_id:None ~at:t2;
    ];
  Alcotest.(check int) "outbox count unchanged" before (Cli.outbox_count db)

(* ---------- run ---------- *)

let () =
  let case name f = Alcotest.test_case name `Quick f in
  Alcotest.run "store uploads"
    [
      ( "migration 5",
        [
          case
            "applies alone on a v4 database (pending ~current:4 starts with \
             it), the table has its nine columns"
            migration_five_from_v4;
        ] );
      ( "put, all, find",
        [
          case "put then find round-trips a row with and without a session"
            put_then_find_round_trips_with_and_without_session;
          case
            "put of the same photo updates in place: 1 row, the second's values"
            put_again_updates_in_place;
          case "all orders by created_at then photo_id"
            all_orders_by_created_at_then_photo_id;
          case "find: None for a photo with no row" find_absent_is_none;
        ] );
      ("remove", [case "removes once, then a no-op" remove_once_then_noop]);
      ( "constraints",
        [
          case "size_bytes = -1 is rejected" negative_size_bytes_rejected;
          case "session_url set with session_created_at null is rejected"
            session_url_without_created_at_rejected;
          case "session_created_at set with session_url null is rejected"
            created_at_without_session_url_rejected;
          case "attempts = -1 is rejected" negative_attempts_rejected;
          case
            "an upload row for an unknown photo is rejected on the foreign key"
            unknown_photo_rejected;
          case "hard-deleting the photo row cascades the upload row away"
            photo_delete_cascades;
        ] );
      ( "not synced",
        [case "put and remove never write to the outbox" never_writes_outbox] );
      ( "Photos.set_upload",
        [
          case
            "on a live photo: the row is updated, and one outbox entry carries \
             the new state, drive_file_id and updated_at"
            set_upload_on_a_live_photo_appends_an_entry;
          case "on a soft-deleted photo: 0 changes, no entry"
            set_upload_on_a_soft_deleted_photo_is_a_noop;
          case
            "Failed without a file id: the payload says failed, drive_file_id \
             null"
            set_upload_failed_without_file_id;
          case "on an unknown photo: 0 changes, no entry"
            set_upload_on_an_unknown_photo_is_a_noop;
        ] );
    ]
