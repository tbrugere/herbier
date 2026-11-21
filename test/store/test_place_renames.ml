(* Native checks of app/store/place_renames.ml (the device-only
   [place_renames] table, migration 7): [Cli.write_ok] runs each
   statement as [Db.write] does on the device (no transaction, no outbox
   entry: [place_renames] is not synced, like test_commune_packs.ml checks
   [commune_packs]). The migration's own insert (which rows get marked) is
   checked in test_store.ml alongside the rest of migration 7. The Capacitor
   plugin itself is a device check (#dev/geocode, « à renommer (place_renames) »
   line). *)

module Observations = Herbier_store.Observations
module Outbox = Herbier_store.Outbox
module Place_renames = Herbier_store.Place_renames
module Ids = Herbier_domain.Ids
module Observation = Herbier_domain.Observation
module Cli = Sqlite_cli

(* ---------- fixtures ---------- *)

let t1 =
  match Ptime.of_rfc3339 "2026-11-21T10:00:00Z" with
  | Ok (t, _, _) -> t
  | Error _ -> invalid_arg "fixture time t1"

let observation_id n =
  match
    Ids.Observation_id.of_string
      (Printf.sprintf "00000000-0000-4000-8000-%012d" n)
  with
  | Some id -> id
  | None -> Alcotest.failf "Observation_id.of_string of test id %d gave None" n

let observation n : Observation.t =
  {
    id = observation_id n;
    plant_id = None;
    at = t1;
    position = Some {Observation.lat = 48.0633; lon = 7.0081; accuracy_m = None};
    place_label = None;
    place_derived = Some "Près de Figeac";
    place_detail = None;
    note = None;
    created_at = t1;
    updated_at = t1;
    deleted_at = None;
  }

(* Seeds an observation (the FK parent) and marks it, as the migration would
   have. *)
let seed_marked db n =
  let (_ : int) =
    Cli.write_ok "observation" db
      (Outbox.bare_stmt
         (Outbox.without_entry (Observations.upsert (observation n))))
  in
  Cli.exec_ok "mark for rename" db
    (Printf.sprintf
       "insert into place_renames (observation_id) values ('%s');\n"
       (Ids.Observation_id.to_string (observation_id n)))

(* ---------- count ---------- *)

let count db =
  match Cli.find db Place_renames.count with
  | Some n -> n
  | None -> Alcotest.fail "Place_renames.count returned no row"

let count_empty_is_zero () =
  let db = Cli.migrated_db () in
  Alcotest.(check int) "count of an empty table" 0 (count db)

let count_counts_marked_rows () =
  let db = Cli.migrated_db () in
  seed_marked db 1;
  seed_marked db 2;
  Alcotest.(check int) "count of two marked rows" 2 (count db)

(* ---------- forget ---------- *)

let forget_once_then_noop () =
  let db = Cli.migrated_db () in
  seed_marked db 1;
  Alcotest.(check int)
    "forget of a marked row: 1 change" 1
    (Cli.write_ok "forget" db (Place_renames.forget (observation_id 1)));
  Alcotest.(check int) "count is 0 after forgetting" 0 (count db);
  Alcotest.(check int)
    "forget again: 0 changes" 0
    (Cli.write_ok "forget again" db (Place_renames.forget (observation_id 1)))

let forget_absent_id_is_a_noop () =
  let db = Cli.migrated_db () in
  Alcotest.(check int)
    "forget of an id that was never marked: 0 changes" 0
    (Cli.write_ok "forget absent" db (Place_renames.forget (observation_id 99)))

let forget_only_the_given_id () =
  let db = Cli.migrated_db () in
  seed_marked db 1;
  seed_marked db 2;
  Alcotest.(check int)
    "forget of one id: 1 change" 1
    (Cli.write_ok "forget" db (Place_renames.forget (observation_id 1)));
  Alcotest.(check int) "the other mark survives" 1 (count db)

(* ---------- cascade ---------- *)

let cascade_on_observation_hard_delete () =
  let db = Cli.migrated_db () in
  seed_marked db 1;
  Cli.exec_ok "hard-delete the observation" db
    (Printf.sprintf
       "pragma foreign_keys = on;\ndelete from observations where id = '%s';\n"
       (Ids.Observation_id.to_string (observation_id 1)));
  Alcotest.(check int)
    "the marker is gone with its observation (on delete cascade)" 0 (count db)

(* ---------- not synced ---------- *)

let never_writes_outbox () =
  let db = Cli.migrated_db () in
  seed_marked db 1;
  let before = Cli.outbox_count db in
  let (_ : int) =
    Cli.write_ok "forget" db (Place_renames.forget (observation_id 1))
  in
  Alcotest.(check int) "outbox count unchanged" before (Cli.outbox_count db)

(* ---------- migration 8 (M8.85): an old « Près de » IGN name renamed ---------- *)

let t2 =
  match Ptime.of_rfc3339 "2026-11-22T10:00:00Z" with
  | Ok (t, _, _) -> t
  | Error _ -> invalid_arg "fixture time t2"

(* An observation inside Figeac named « Près de Figeac » by « IGN en ligne »
   under M5.83, its migration 7 marker already forgotten: migration 8 marks
   it again, and the pass's guarded rename writes « À Figeac ». *)
let migration_8_then_rename () =
  let db = Cli.fresh_db () in
  Cli.apply_migrations db
    (List.filter
       (fun (m : Herbier_store.Schema.migration) -> m.version <= 7)
       Herbier_store.Schema.migrations);
  let lat = 44.602 and lon = 2.03 in
  let o =
    {
      (observation 1) with
      position = Some {Observation.lat; lon; accuracy_m = None};
    }
  in
  let (_ : int) =
    Cli.write_ok "observation" db
      (Outbox.bare_stmt (Outbox.without_entry (Observations.upsert o)))
  in
  Alcotest.(check int) "no marker before migration 8" 0 (count db);
  Cli.migrate db ~current:7;
  Alcotest.(check (list string))
    "to_rename lists it"
    [Ids.Observation_id.to_string o.id]
    (List.map
       (fun (o : Observation.t) -> Ids.Observation_id.to_string o.id)
       (Cli.all db Observations.to_rename));
  Alcotest.(check int)
    "renamed: 1 change" 1
    (Cli.write_ok "rename" db
       (Outbox.bare_stmt
          (Outbox.without_entry
             (Observations.rename_place_derived o.id ~lat ~lon
                ~was:"Près de Figeac" ~detail:None "À Figeac" ~at:t2))));
  Alcotest.(check (option string))
    "the stored name" (Some "À Figeac")
    (Option.bind
       (Cli.find db (Observations.get o.id))
       (fun (o : Observation.t) -> o.place_derived))

(* ---------- run ---------- *)

let () =
  let case name f = Alcotest.test_case name `Quick f in
  Alcotest.run "store place_renames"
    [
      ( "count",
        [
          case "count of an empty table is 0" count_empty_is_zero;
          case "count counts every marked row" count_counts_marked_rows;
        ] );
      ( "forget",
        [
          case "forget gives 1 then 0" forget_once_then_noop;
          case "forget of an id never marked gives 0" forget_absent_id_is_a_noop;
          case "forget removes only the given id" forget_only_the_given_id;
        ] );
      ( "cascade",
        [
          case "deleting the observation deletes its marker too"
            cascade_on_observation_hard_delete;
        ] );
      ( "migration 8",
        [
          case "an old « Près de Figeac » is marked, then renamed « À Figeac »"
            migration_8_then_rename;
        ] );
      ( "not synced",
        [case "forget never writes to the outbox" never_writes_outbox] );
    ]
