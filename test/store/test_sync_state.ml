(* Native checks of app/store/sync_state.ml (the local sync_state table):
   through the sqlite3 CLI, as test_outbox.ml checks Outbox. Device checks
   (#dev/sync) cover the Capacitor plugin itself. *)

module Value = Herbier_test_support.Value
module Codec = Herbier_store.Codec
module Outbox = Herbier_store.Outbox
module Sync_state = Herbier_store.Sync_state
module Cli = Sqlite_cli

let time = Value.time

(* Keeps microseconds, as Codec.timestamp's format does. *)
let t_plants = time "2026-11-01T09:00:00.123456Z"
let t_tags = time "2026-11-01T09:00:01.654321Z"
let t_plants_later = time "2026-11-02T10:00:00.000001Z"

let ptime_us =
  (* Equality to the microsecond: Codec.timestamp truncates beyond that, so a
     testable on the exact instant is enough (round_trip below never produces
     sub-microsecond values). *)
  Alcotest.testable
    (fun f t ->
      Format.pp_print_string f (Ptime.to_rfc3339 ~frac_s:6 ~tz_offset_s:0 t))
    Ptime.equal

let cursor = Alcotest.(pair string ptime_us)
let cursor_of db table = List.assoc_opt table (Cli.all db Sync_state.all)

let all_on_a_fresh_db_is_empty () =
  let db = Cli.migrated_db () in
  Alcotest.(check (list cursor)) "no cursor yet" [] (Cli.all db Sync_state.all)

let set_then_all_round_trips_the_microsecond () =
  let db = Cli.migrated_db () in
  let (_ : int) =
    Cli.write_ok "set plants" db (Sync_state.set ~table_name:"plants" t_plants)
  in
  Alcotest.(check (option ptime_us))
    "all gives back the same instant to the microsecond" (Some t_plants)
    (cursor_of db "plants")

let an_unset_table_has_no_cursor () =
  let db = Cli.migrated_db () in
  Alcotest.(check (option ptime_us))
    "no cursor for tags" None (cursor_of db "tags")

let set_twice_on_one_table_gives_one_row_the_second_value () =
  let db = Cli.migrated_db () in
  let (_ : int) =
    Cli.write_ok "first set" db (Sync_state.set ~table_name:"plants" t_plants)
  in
  Alcotest.(check int)
    "the second set changes 1 row" 1
    (Cli.write_ok "second set" db
       (Sync_state.set ~table_name:"plants" t_plants_later));
  Alcotest.(check (option ptime_us))
    "all gives the second value" (Some t_plants_later) (cursor_of db "plants");
  Alcotest.(check int)
    "still one row in sync_state" 1
    (Cli.count db "select count(*) as n from sync_state;\n")

let all_is_sorted_by_table_name () =
  let db = Cli.migrated_db () in
  let (_ : int) =
    Cli.write_ok "set tags" db (Sync_state.set ~table_name:"tags" t_tags)
  in
  let (_ : int) =
    Cli.write_ok "set plants" db (Sync_state.set ~table_name:"plants" t_plants)
  in
  let (_ : int) =
    Cli.write_ok "set observations" db
      (Sync_state.set ~table_name:"observations" t_plants)
  in
  Alcotest.(check (list string))
    "by table_name"
    ["observations"; "plants"; "tags"]
    (List.map fst (Cli.all db Sync_state.all))

let reset_clears_every_cursor () =
  let db = Cli.migrated_db () in
  let (_ : int) =
    Cli.write_ok "set plants" db (Sync_state.set ~table_name:"plants" t_plants)
  in
  let (_ : int) =
    Cli.write_ok "set tags" db (Sync_state.set ~table_name:"tags" t_tags)
  in
  Alcotest.(check int)
    "reset changes every row" 2
    (Cli.write_ok "reset" db Sync_state.reset);
  Alcotest.(check (list cursor)) "no cursor left" [] (Cli.all db Sync_state.all)

let () =
  let case name f = Alcotest.test_case name `Quick f in
  Alcotest.run "store sync_state"
    [
      ( "Sync_state",
        [
          case "all on a migrated db is []" all_on_a_fresh_db_is_empty;
          case "set then all gives back the same Ptime.t to the microsecond"
            set_then_all_round_trips_the_microsecond;
          case "a table never set has no cursor" an_unset_table_has_no_cursor;
          case "set twice on one table: one row, the second value"
            set_twice_on_one_table_gives_one_row_the_second_value;
          case "all is sorted by table name" all_is_sorted_by_table_name;
          case "reset deletes every cursor" reset_clears_every_cursor;
        ] );
    ]
