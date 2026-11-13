(* Native checks of app/store/commune_packs.ml (the device-only
   [commune_packs] table, migration 4) through the sqlite3 CLI, exactly as
   test_ref_images.ml checks Ref_images: Cli.write_ok runs each statement as
   [Db.write] does on the device (no transaction, no outbox entry:
   [commune_packs] is not synced). The Capacitor plugin itself and the file it
   points at are a device check (#dev/geocode, "IGN hors-ligne" line). *)

module Schema = Herbier_store.Schema
module Commune_packs = Herbier_store.Commune_packs
module Cli = Sqlite_cli
module Text = Herbier_test_support.Text

(* ---------- fixtures ---------- *)

let t1 =
  match Ptime.of_rfc3339 "2026-11-12T10:00:00Z" with
  | Ok (t, _, _) -> t
  | Error _ -> invalid_arg "fixture time t1"

let t2 =
  match Ptime.of_rfc3339 "2026-11-12T11:30:05.5+01:00" with
  | Ok (t, _, _) -> t
  | Error _ -> invalid_arg "fixture time t2"

let row ?(departement = "90") ?(name = "Territoire de Belfort")
    ?(path = "communes/90-1.json") ?(size_bytes = 109_832) ?(communes = 101)
    ?(downloaded_at = t1) () : Commune_packs.t =
  {departement; name; path; size_bytes; communes; downloaded_at}

(* ---------- testables ---------- *)

let row_json (r : Commune_packs.t) =
  `Assoc
    [
      ("departement", `String r.departement);
      ("name", `String r.name);
      ("path", `String r.path);
      ("size_bytes", `Int r.size_bytes);
      ("communes", `Int r.communes);
      ( "downloaded_at",
        `String (Ptime.to_rfc3339 ~tz_offset_s:0 r.downloaded_at) );
    ]

let rows_json l = `List (List.map row_json l)

let check_rows what expected actual =
  Alcotest.(check Cli.yojson) what (rows_json expected) (rows_json actual)

(* ---------- migration 4 ---------- *)

let migration_four_from_v3 () =
  let db = Cli.fresh_db () in
  (match Schema.migrations with
  | m1 :: m2 :: m3 :: _ -> Cli.apply_migrations db [m1; m2; m3]
  | _ -> Alcotest.fail "need at least three migrations");
  Alcotest.(check int)
    "after migrations 1-3, user_version is 3" 3 (Cli.user_version db);
  Alcotest.(check int)
    "commune_packs does not exist yet" 0
    (Cli.count db
       "select count(*) as n from sqlite_master where type = 'table' and name \
        = 'commune_packs';\n");
  (match Schema.pending ~current:3 with
  | Ok [m] ->
      Alcotest.(check int) "pending ~current:3 is migration 4 alone" 4 m.version
  | Ok ms ->
      Alcotest.failf
        "pending ~current:3: expected exactly one migration, got %d"
        (List.length ms)
  | Error (Schema.Unknown_version _) ->
      Alcotest.fail "expected Ok [migration 4]");
  Cli.migrate db ~current:3;
  Alcotest.(check int) "latest is 4" 4 Schema.latest;
  Alcotest.(check int)
    "user_version after migrating is 4" 4 (Cli.user_version db);
  Alcotest.(check (list string))
    "commune_packs columns"
    (List.sort String.compare
       [
         "departement"; "name"; "path"; "size_bytes"; "communes"; "downloaded_at";
       ])
    (Cli.column_names db "commune_packs")

(* ---------- put, all, find ---------- *)

let put_then_all_round_trips () =
  let db = Cli.migrated_db () in
  let r = row () in
  Alcotest.(check int)
    "put: 1 change" 1
    (Cli.write_ok "put" db (Commune_packs.put r));
  check_rows "round trip" [r] (Cli.all db Commune_packs.all)

let put_again_replaces () =
  let db = Cli.migrated_db () in
  let v1 = row ~path:"communes/90-1.json" ~downloaded_at:t1 () in
  let v2 =
    row ~name:"Territoire de Belfort" ~path:"communes/90-2.json"
      ~size_bytes:110_000 ~downloaded_at:t2 ()
  in
  let (_ : int) = Cli.write_ok "put v1" db (Commune_packs.put v1) in
  let (_ : int) = Cli.write_ok "put v2 (same code)" db (Commune_packs.put v2) in
  check_rows "one row, the second's values" [v2] (Cli.all db Commune_packs.all)

let order_by_departement () =
  let db = Cli.migrated_db () in
  let belfort = row ~departement:"90" ~path:"communes/90-1.json" () in
  let corse =
    row ~departement:"2A" ~name:"Corse-du-Sud" ~path:"communes/2A-1.json"
      ~communes:124 ()
  in
  (* Put in an order different from the department code order. *)
  let (_ : int) = Cli.write_ok "put 90" db (Commune_packs.put belfort) in
  let (_ : int) = Cli.write_ok "put 2A" db (Commune_packs.put corse) in
  check_rows "2A before 90" [corse; belfort] (Cli.all db Commune_packs.all)

let find_present_absent () =
  let db = Cli.migrated_db () in
  let (_ : int) = Cli.write_ok "put" db (Commune_packs.put (row ())) in
  (match Cli.find db (Commune_packs.find "90") with
  | Some r -> Alcotest.(check string) "departement" "90" r.departement
  | None -> Alcotest.fail "expected a row for 90");
  Alcotest.(check bool)
    "68 is absent" true
    (Option.is_none (Cli.find db (Commune_packs.find "68")))

let remove_once_then_noop () =
  let db = Cli.migrated_db () in
  let (_ : int) = Cli.write_ok "put" db (Commune_packs.put (row ())) in
  Alcotest.(check int)
    "first remove: 1 change" 1
    (Cli.write_ok "remove" db (Commune_packs.remove ~departement:"90"));
  Alcotest.(check int)
    "second remove: 0 changes" 0
    (Cli.write_ok "remove again" db (Commune_packs.remove ~departement:"90"));
  check_rows "no row left" [] (Cli.all db Commune_packs.all)

(* ---------- constraints ---------- *)

let insert_sql ?(departement = "'90'") ?(name = "'Territoire de Belfort'")
    ?(path = "'communes/90-1.json'") ?(size_bytes = "109832")
    ?(communes = "101") ?(downloaded_at = "'2026-11-12T10:00:00.000000Z'") () =
  Printf.sprintf
    "insert into commune_packs (departement, name, path, size_bytes, communes, \
     downloaded_at) values (%s, %s, %s, %s, %s, %s);\n"
    departement name path size_bytes communes downloaded_at

let rejected what ~because db sql =
  match Cli.sqlite db sql with
  | Ok out -> Alcotest.failf "%s should be rejected, got %s" what out
  | Error e -> (
      match Text.contains ~sub:because e with
      | true -> ()
      | false ->
          Alcotest.failf "%s should be rejected for %S, got %s" what because e)

let blank_name_rejected () =
  let db = Cli.migrated_db () in
  rejected "a blank name" ~because:"CHECK constraint failed" db
    (insert_sql ~name:"'   '" ())

let zero_communes_rejected () =
  let db = Cli.migrated_db () in
  rejected "communes = 0" ~because:"CHECK constraint failed" db
    (insert_sql ~communes:"0" ())

let negative_size_rejected () =
  let db = Cli.migrated_db () in
  rejected "a negative size_bytes" ~because:"CHECK constraint failed" db
    (insert_sql ~size_bytes:"-1" ())

let duplicate_path_rejected () =
  let db = Cli.migrated_db () in
  Cli.exec_ok "first row" db (insert_sql ~departement:"'90'" ());
  rejected "a second department with the same path"
    ~because:"UNIQUE constraint failed" db
    (insert_sql ~departement:"'68'" ~name:"'Nord'" ())

(* ---------- a stored row that does not decode ---------- *)

let undecodable_row_is_an_error () =
  let db = Cli.migrated_db () in
  Cli.exec_ok "a row with a malformed downloaded_at" db
    (insert_sql ~downloaded_at:"'not a time'" ());
  match Cli.all_results db Commune_packs.all with
  | [Error _] -> ()
  | [Ok _] -> Alcotest.fail "expected a decoding error, got a row"
  | rows -> Alcotest.failf "expected exactly one row, got %d" (List.length rows)

(* ---------- not synced ---------- *)

let never_writes_outbox () =
  let db = Cli.migrated_db () in
  let before = Cli.outbox_count db in
  let r = row () in
  let (_ : int) = Cli.write_ok "put" db (Commune_packs.put r) in
  let (_ : int) =
    Cli.write_ok "remove" db (Commune_packs.remove ~departement:r.departement)
  in
  Alcotest.(check int) "outbox count unchanged" before (Cli.outbox_count db)

(* ---------- run ---------- *)

let () =
  let case name f = Alcotest.test_case name `Quick f in
  Alcotest.run "store commune_packs"
    [
      ( "migration 4",
        [
          case
            "applies on a v3 database, latest is 4, pending ~current:3 is \
             migration 4 alone, the table has its six columns"
            migration_four_from_v3;
        ] );
      ( "put, all, find",
        [
          case "put then all round-trips a row (Ptime equal)"
            put_then_all_round_trips;
          case "put of the same department replaces: 1 row, the second's values"
            put_again_replaces;
          case "all orders by department code (2A before 90)"
            order_by_departement;
          case "find: 1 row for a known code, none for an absent one"
            find_present_absent;
        ] );
      ("remove", [case "removes once, then a no-op" remove_once_then_noop]);
      ( "constraints",
        [
          case "a blank name is rejected" blank_name_rejected;
          case "communes = 0 is rejected" zero_communes_rejected;
          case "a negative size_bytes is rejected" negative_size_rejected;
          case "a duplicate path under another department code is rejected"
            duplicate_path_rejected;
        ] );
      ( "decoding",
        [
          case "a stored row that does not decode is an error, not skipped"
            undecodable_row_is_an_error;
        ] );
      ( "not synced",
        [case "put and remove never write to the outbox" never_writes_outbox] );
    ]
