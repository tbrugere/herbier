(* Native checks of app/store/{codec,schema}.ml against the sqlite3 CLI: the
   migration SQL (each string is one statement, run in order in one
   transaction as the plugin's executeSet runs it; it creates the tables of
   Tables and the lookup tables holding the domain's values, constraints as on
   the server) and the codec (parameters written by Codec.param read back
   through Codec.decode). Migration 2 (the FTS5 search table and its
   triggers) is checked here for its objects and its upgrade paths; what the
   triggers keep in the index is in test_queries. *)

module Col = Postgrest.Col
module Row = Postgrest.Row
module Ids = Herbier_domain.Ids
module Photo = Herbier_domain.Photo
module Source = Herbier_domain.Reference.Source
module Status = Herbier_domain.Reference.Status
module Organ = Herbier_domain.Reference.Organ
module P = Tables.Plants
module Cli = Sqlite_cli

let contains = Cli.contains
let replace_all = Cli.replace_all
let sqlite = Cli.sqlite
let exec_ok = Cli.exec_ok
let rows = Cli.rows
let string_field = Cli.string_field
let int_field = Cli.int_field
let user_version = Cli.user_version
let names_of = Cli.names_of
let table_names = Cli.table_names
let column_names = Cli.column_names
let sql_literal = Cli.sql_literal
let fresh_db = Cli.fresh_db
let migrated_db = Cli.migrated_db
let migrate = Cli.migrate
let string_of_codec_error = Cli.string_of_codec_error
let param = Cli.param
let codec_error = Cli.codec_error
let yojson = Cli.yojson
let ptime = Cli.ptime

(* ---------- schema facts ---------- *)

let name (c : (_, _, _) Col.t) = c.name
let tname t = Col.name_of_table t

type column = {name : string; not_null : bool; sql_type : string}

(* The local SQLite type of a Col base (architecture §3). *)
let sql_type : type a. a Col.base -> string = function
  | Integer | Bool -> "integer"
  | Numeric -> "real"
  | Str | TimestampTz | JSON | Custom _ -> "text"

(* A column of Tables: its name, whether it is Not_Null, its local type. *)
let col : type a. (_, a, _) Col.t -> column =
 fun c ->
  match c.ty with
  | Not_Null base -> {name = c.name; not_null = true; sql_type = sql_type base}
  | Nullable base -> {name = c.name; not_null = false; sql_type = sql_type base}

let synced_tables : (string * column list) list =
  [
    ( tname P.table,
      [
        col P.id;
        col P.display_name;
        col P.aliases;
        col P.scientific_name;
        col P.authorship;
        col P.gbif_key;
        col P.notes;
        col P.notes_updated_at;
        col P.cover_photo_id;
        col P.created_at;
        col P.updated_at;
        col P.deleted_at;
      ] );
    (let module T = Tables.Observations in
     ( tname T.table,
       [
         col T.id;
         col T.plant_id;
         col T.at;
         col T.lat;
         col T.lon;
         col T.accuracy_m;
         col T.place_label;
         col T.place_derived;
         col T.note;
         col T.created_at;
         col T.updated_at;
         col T.deleted_at;
       ] ));
    (let module T = Tables.Photos in
     ( tname T.table,
       [
         col T.id;
         col T.observation_id;
         col T.taken_at;
         col T.width;
         col T.height;
         col T.sha256;
         col T.preview_path;
         col T.preview_bucket_key;
         col T.original_target;
         col T.drive_file_id;
         col T.upload_state;
         col T.created_at;
         col T.updated_at;
         col T.deleted_at;
       ] ));
    (let module T = Tables.Tags in
     ( tname T.table,
       [
         col T.id;
         col T.name;
         col T.created_at;
         col T.updated_at;
         col T.deleted_at;
       ] ));
    (let module T = Tables.Plant_tags in
     ( tname T.table,
       [
         col T.id;
         col T.plant_id;
         col T.tag_id;
         col T.created_at;
         col T.updated_at;
         col T.deleted_at;
       ] ));
    (let module T = Tables.Plant_refs in
     ( tname T.table,
       [
         col T.id;
         col T.plant_id;
         col T.source;
         col T.external_id;
         col T.url;
         col T.created_at;
         col T.updated_at;
         col T.deleted_at;
       ] ));
    (let module T = Tables.Reference in
     ( tname T.table,
       [
         col T.id;
         col T.plant_id;
         col T.source;
         col T.fetched_at;
         col T.payload;
         col T.status;
         col T.created_at;
         col T.updated_at;
         col T.deleted_at;
       ] ));
  ]

(* Name and local type of each column of the local-only tables. *)
let local_tables : (string * (string * string) list) list =
  [
    ( "outbox",
      [
        ("seq", "integer");
        ("table_name", "text");
        ("row_id", "text");
        ("op", "text");
        ("payload_json", "text");
        ("created_at", "text");
        ("attempts", "integer");
        ("last_error", "text");
      ] );
    ("sync_state", [("table_name", "text"); ("last_pulled_at", "text")]);
    ("settings", [("key", "text"); ("value", "text")]);
    ( "ref_images",
      [
        ("plant_id", "text");
        ("source", "text");
        ("organ", "text");
        ("remote_url", "text");
        ("licence", "text");
        ("attribution", "text");
        ("thumb_path", "text");
      ] );
  ]

(* Each lookup table and the values it must hold: the to_string of every
   constructor of its domain module, as the server's lookup tables. *)
let lookup_tables : (string * string list) list =
  [
    ("reference_sources", List.map Source.to_string Source.all);
    ("reference_statuses", List.map Status.to_string Status.all);
    ( "photo_original_targets",
      List.map Photo.Original_target.to_string Photo.Original_target.all );
    ( "photo_upload_states",
      List.map Photo.Upload_state.to_string Photo.Upload_state.all );
    ("reference_organs", List.map Organ.to_string Organ.all);
  ]

let lookup_columns =
  List.map (fun (t, _) -> (t, [("value", "text")])) lookup_tables

let all_tables =
  List.sort String.compare
    (List.map fst synced_tables
    @ List.map fst local_tables
    @ List.map fst lookup_tables)

(* ---------- Schema ---------- *)

let string_of_pending = function
  | Ok ms ->
      Printf.sprintf "Ok [%s]"
        (String.concat "; "
           (List.map (fun (m : Schema.migration) -> string_of_int m.version) ms))
  | Error (Schema.Unknown_version {found; latest}) ->
      Printf.sprintf "Error (Unknown_version {found = %d; latest = %d})" found
        latest

let versions_ascending () =
  let versions =
    List.map (fun (m : Schema.migration) -> m.version) Schema.migrations
  in
  Alcotest.(check (list int))
    "versions are 1..n without gap"
    (List.init (List.length versions) (fun i -> i + 1))
    versions;
  Alcotest.(check int) "latest is 3" 3 Schema.latest;
  Alcotest.(check (option int))
    "latest is the last version" (Some Schema.latest)
    (match List.rev versions with last :: _ -> Some last | [] -> None)

let pending_from_zero () =
  Alcotest.(check string)
    "pending from 0 is every migration"
    (Printf.sprintf "Ok [%s]"
       (String.concat "; "
          (List.init Schema.latest (fun i -> string_of_int (i + 1)))))
    (string_of_pending (Schema.pending ~current:0))

let pending_at_latest () =
  Alcotest.(check string)
    "pending at latest is empty" "Ok []"
    (string_of_pending (Schema.pending ~current:Schema.latest))

let pending_from_one () =
  Alcotest.(check string)
    "pending from 1 is migrations 2 and 3" "Ok [2; 3]"
    (string_of_pending (Schema.pending ~current:1))

let pending_from_two () =
  Alcotest.(check string)
    "pending from 2 is migration 3 alone" "Ok [3]"
    (string_of_pending (Schema.pending ~current:2))

let pending_above_latest () =
  Alcotest.(check string)
    "a version above latest is unknown"
    (Printf.sprintf "Error (Unknown_version {found = %d; latest = %d})"
       (Schema.latest + 1) Schema.latest)
    (string_of_pending (Schema.pending ~current:(Schema.latest + 1)))

let pending_negative () =
  Alcotest.(check string)
    "a negative version is unknown"
    (Printf.sprintf "Error (Unknown_version {found = -1; latest = %d})"
       Schema.latest)
    (string_of_pending (Schema.pending ~current:(-1)))

let batch_appends_version () =
  List.iter
    (fun (m : Schema.migration) ->
      Alcotest.(check (list string))
        (Printf.sprintf "batch %d is its statements then the version pragma"
           m.version)
        (m.statements @ [Printf.sprintf "pragma user_version = %d" m.version])
        (Schema.batch m))
    Schema.migrations

(* The plugin compiles each string of the set on its own, and Android's
   compiler ignores the text after a first statement, so a string holding two
   statements would lose the second on the device while the CLI runs both.
   Each string runs alone here, in order, under ".trace --profile", which
   prints every statement SQLite ran followed by " -- <n> ns": the whole
   string must come out as one statement. *)
let one_statement_per_string () =
  let db = fresh_db () in
  List.iter
    (fun (m : Schema.migration) ->
      List.iteri
        (fun i statement ->
          let what = Printf.sprintf "migration %d, string %d" m.version i in
          match
            sqlite db (".trace stdout --profile\n" ^ statement ^ "\n;\n")
          with
          | Error e -> Alcotest.failf "%s: %s" what e
          | Ok out ->
              Alcotest.(check bool)
                (what ^ " is one statement")
                true
                (contains ~sub:(statement ^ "\n; -- ") out))
        (Schema.batch m))
    Schema.migrations

(* ---------- migrations run through sqlite3 ---------- *)

let search_triggers =
  List.sort String.compare
    [
      "plants_search_ai";
      "plants_search_au";
      "plants_search_ad";
      "plant_tags_search_ai";
      "plant_tags_search_au";
      "plant_tags_search_ad";
      "tags_search_au";
      "observations_search_ai";
      "observations_search_au";
      "observations_search_ad";
    ]

let check_at_latest what db =
  Alcotest.(check int)
    (what ^ ": user_version is latest")
    Schema.latest (user_version db);
  Alcotest.(check (list string))
    (what ^ ": the sixteen tables exist")
    all_tables (table_names db);
  Alcotest.(check (list string))
    (what ^ ": the search triggers exist")
    search_triggers (Cli.trigger_names db);
  Alcotest.(check int)
    (what ^ ": plant_search is an fts5 table with the decided tokenizer")
    1
    (Cli.count db
       "select count(*) as n from sqlite_master where name = 'plant_search' \
        and lower(sql) like '%using fts5%' and lower(sql) like '%unicode61 \
        remove_diacritics 2%';\n")

let fresh_install () =
  let db = fresh_db () in
  migrate db ~current:0;
  check_at_latest "fresh install" db

let upgrade_from_empty () =
  let db = fresh_db () in
  exec_ok "empty database" db "create table x (a);\ndrop table x;\n";
  Alcotest.(check (list string))
    "the empty file has no table" [] (table_names db);
  let current = user_version db in
  Alcotest.(check int) "an empty file is at version 0" 0 current;
  migrate db ~current;
  check_at_latest "upgrade from empty" db;
  Alcotest.(check string)
    "reopening at the read version applies nothing" "Ok []"
    (string_of_pending (Schema.pending ~current:(user_version db)))

let upgrade_from_version_1 () =
  let db = fresh_db () in
  (match Schema.migrations with
  | m :: _ -> Cli.apply_migrations db [m]
  | [] -> Alcotest.fail "no migration");
  Alcotest.(check int)
    "after migration 1 alone, user_version is 1" 1 (user_version db);
  Alcotest.(check (list string))
    "at version 1 there is no trigger" [] (Cli.trigger_names db);
  migrate db ~current:1;
  check_at_latest "upgrade from 1" db

let columns () =
  let db = migrated_db () in
  List.iter
    (fun (table, expected) ->
      Alcotest.(check (list string))
        (Printf.sprintf "columns of %s" table)
        (List.sort String.compare expected)
        (column_names db table))
    (List.map
       (fun (t, cols) -> (t, List.map (fun c -> c.name) cols))
       synced_tables
    @ List.map
        (fun (t, cols) -> (t, List.map fst cols))
        (local_tables @ lookup_columns))

(* When the database has both columns, in any tables, the plugin rewrites
   every DELETE into an UPDATE (Database.deleteSQL); neither name is used
   anywhere. *)
let no_plugin_reserved_columns () =
  let db = migrated_db () in
  List.iter
    (fun table ->
      Alcotest.(check (list string))
        (Printf.sprintf "%s has no sql_deleted or last_modified column" table)
        []
        (List.filter
           (fun c -> c = "sql_deleted" || c = "last_modified")
           (column_names db table)))
    (table_names db)

(* Through type affinity a wrong declared type changes what is stored (an
   integer column turns '1234' into 1234), which Row then rejects. *)
let types () =
  let db = migrated_db () in
  let declared table =
    rows db (Printf.sprintf "pragma table_info(%s);\n" table)
    |> List.map (fun row ->
        ( string_field "name" row,
          String.lowercase_ascii (string_field "type" row) ))
    |> List.sort compare
  in
  List.iter
    (fun (table, expected) ->
      Alcotest.(check (list (pair string string)))
        (Printf.sprintf "local types of %s" table)
        (List.sort compare expected)
        (declared table))
    (List.map
       (fun (t, cols) -> (t, List.map (fun c -> (c.name, c.sql_type)) cols))
       synced_tables
    @ local_tables
    @ lookup_columns)

(* SQLite's pragma table_info says notnull = 0 for a text primary key
   declared without not null, so ids are covered too. *)
let nullability () =
  let db = migrated_db () in
  List.iter
    (fun (table, cols) ->
      let not_null =
        rows db (Printf.sprintf "pragma table_info(%s);\n" table)
        |> List.filter (fun row -> int_field "notnull" row = 1)
        |> List.map (string_field "name")
        |> List.sort String.compare
      in
      Alcotest.(check (list string))
        (Printf.sprintf "not null columns of %s are the Not_Null ones" table)
        (List.sort String.compare
           (List.filter_map
              (fun c ->
                match c.not_null with true -> Some c.name | false -> None)
              cols))
        not_null)
    synced_tables

let indexes () =
  let db = migrated_db () in
  let present =
    names_of db
      "select name from sqlite_master where type = 'index' and name not like \
       'sqlite_%';\n"
  in
  List.iter
    (fun idx ->
      Alcotest.(check bool)
        (Printf.sprintf "index %s exists" idx)
        true (List.mem idx present))
    [
      "observations_plant_id_idx";
      "photos_observation_id_idx";
      "plant_tags_tag_id_idx";
      "plants_cover_photo_id_idx";
    ]

(* ---------- constraints ---------- *)

let fk_on = "pragma foreign_keys = on;\n"
let t0 = "'2026-10-28T12:00:00.000000Z'"
let plant_a = "00000000-0000-4000-8000-00000000000a"
let plant_b = "00000000-0000-4000-8000-00000000000b"
let missing = "00000000-0000-4000-8000-0000000000ff"

let plant_sql ?(cover = "NULL") id =
  Printf.sprintf
    "insert into plants (id, display_name, aliases, notes, cover_photo_id, \
     created_at, updated_at) values ('%s', 'p', '[]', '', %s, %s, %s);\n"
    id cover t0 t0

(* Migration 3 adds ref_images and reference_organs only: a database at
   version 2 with a row keeps it after upgrading to 3. *)
let upgrade_from_version_2_keeps_rows () =
  let db = fresh_db () in
  (match Schema.migrations with
  | m1 :: m2 :: _ -> Cli.apply_migrations db [m1; m2]
  | _ -> Alcotest.fail "need at least two migrations");
  Alcotest.(check int)
    "after migrations 1 and 2, user_version is 2" 2 (user_version db);
  exec_ok "seed one plant" db (fk_on ^ plant_sql plant_a);
  migrate db ~current:2;
  check_at_latest "upgrade from 2" db;
  Alcotest.(check int)
    "the plant survives the migration to 3" 1
    (Cli.count db "select count(*) as n from plants;\n")

let observation_sql ?(plant = "NULL") ?(lat = "NULL") ?(lon = "NULL")
    ?(accuracy = "NULL") id =
  Printf.sprintf
    "insert into observations (id, plant_id, at, lat, lon, accuracy_m, \
     created_at, updated_at) values ('%s', %s, %s, %s, %s, %s, %s, %s);\n"
    id plant t0 lat lon accuracy t0 t0

let tag_sql id =
  Printf.sprintf
    "insert into tags (id, name, created_at, updated_at) values ('%s', 't', \
     %s, %s);\n"
    id t0 t0

let plant_tag_sql id ~plant ~tag =
  Printf.sprintf
    "insert into plant_tags (id, plant_id, tag_id, created_at, updated_at) \
     values ('%s', '%s', '%s', %s, %s);\n"
    id plant tag t0 t0

let photo_sql id ~observation =
  Printf.sprintf
    "insert into photos (id, observation_id, taken_at, width, height, sha256, \
     preview_path, original_target, upload_state, created_at, updated_at) \
     values ('%s', '%s', %s, 1, 1, 'h', 'p', '%s', '%s', %s, %s);\n"
    id observation t0
    (Photo.Original_target.to_string Drive)
    (Photo.Upload_state.to_string Pending)
    t0 t0

let reference_sql id ~plant ~source =
  Printf.sprintf
    "insert into reference (id, plant_id, source, fetched_at, payload, status, \
     created_at, updated_at) values ('%s', '%s', '%s', %s, '{}', '%s', %s, %s);\n"
    id plant (Source.to_string source) t0
    (Status.to_string Complete)
    t0 t0

let plant_ref_sql id ~plant ~source =
  Printf.sprintf
    "insert into plant_refs (id, plant_id, source, external_id, url, \
     created_at, updated_at) values ('%s', '%s', '%s', '1', 'https://x', %s, \
     %s);\n"
    id plant (Source.to_string source) t0 t0

let accepted what db sql =
  match sqlite db (fk_on ^ sql) with
  | Ok _ -> ()
  | Error e -> Alcotest.failf "%s should be accepted: %s" what e

(* [because] is a part of sqlite3's message, so a rejection for another reason
   fails. *)
let rejected what ~because db sql =
  match sqlite db (fk_on ^ sql) with
  | Ok _ -> Alcotest.failf "%s should be rejected" what
  | Error e -> (
      match contains ~sub:because e with
      | true -> ()
      | false ->
          Alcotest.failf "%s should be rejected for %S, got %s" what because e)

let quoted s = "'" ^ s ^ "'"

let foreign_keys () =
  let db = migrated_db () in
  accepted "a plant" db (plant_sql plant_a);
  rejected "an observation of an absent plant"
    ~because:"FOREIGN KEY constraint failed" db
    (observation_sql ~plant:(quoted missing)
       "00000000-0000-4000-8000-000000000001");
  accepted "an observation of an existing plant" db
    (observation_sql ~plant:(quoted plant_a)
       "00000000-0000-4000-8000-000000000002");
  accepted "an observation with no plant" db
    (observation_sql "00000000-0000-4000-8000-000000000003");
  accepted "a plant whose cover photo is unknown" db
    (plant_sql ~cover:(quoted missing) plant_b);
  rejected "a photo of an absent observation"
    ~because:"FOREIGN KEY constraint failed" db
    (photo_sql "00000000-0000-4000-8000-0000000000f1" ~observation:missing);
  rejected "a plant_tags row of an absent tag"
    ~because:"FOREIGN KEY constraint failed" db
    (plant_tag_sql "00000000-0000-4000-8000-0000000000d1" ~plant:plant_a
       ~tag:missing);
  rejected "a plant_tags row of an absent plant"
    ~because:"FOREIGN KEY constraint failed" db
    (tag_sql "00000000-0000-4000-8000-0000000000c1"
    ^ plant_tag_sql "00000000-0000-4000-8000-0000000000d2" ~plant:missing
        ~tag:"00000000-0000-4000-8000-0000000000c1");
  rejected "a plant_refs row of an absent plant"
    ~because:"FOREIGN KEY constraint failed" db
    (plant_ref_sql "00000000-0000-4000-8000-0000000000e1" ~plant:missing
       ~source:Source.Gbif);
  rejected "a reference row of an absent plant"
    ~because:"FOREIGN KEY constraint failed" db
    (reference_sql "00000000-0000-4000-8000-0000000000b1" ~plant:missing
       ~source:Source.Gbif)

let delete_cascades () =
  let db = migrated_db () in
  let obs = "00000000-0000-4000-8000-000000000001" in
  let tag = "00000000-0000-4000-8000-0000000000c1" in
  accepted "a plant with an observation, a photo, a tag, a ref, a reference" db
    (plant_sql plant_a
    ^ observation_sql ~plant:(quoted plant_a) obs
    ^ photo_sql "00000000-0000-4000-8000-0000000000f1" ~observation:obs
    ^ tag_sql tag
    ^ plant_tag_sql "00000000-0000-4000-8000-0000000000d1" ~plant:plant_a ~tag
    ^ plant_ref_sql "00000000-0000-4000-8000-0000000000e1" ~plant:plant_a
        ~source:Source.Gbif
    ^ reference_sql "00000000-0000-4000-8000-0000000000b1" ~plant:plant_a
        ~source:Source.Gbif);
  accepted "deleting the plant" db
    (Printf.sprintf "delete from plants where id = '%s';\n" plant_a);
  List.iter
    (fun table ->
      Alcotest.(check int)
        (Printf.sprintf "%s rows went with their plant" table)
        0
        (List.length (rows db (Printf.sprintf "select id from %s;\n" table))))
    ["observations"; "photos"; "plant_tags"; "plant_refs"; "reference"];
  Alcotest.(check int)
    "the tag stays" 1
    (List.length (rows db "select id from tags;\n"));
  accepted "a second tag link" db
    (plant_sql plant_b
    ^ plant_tag_sql "00000000-0000-4000-8000-0000000000d2" ~plant:plant_b ~tag);
  accepted "deleting the tag" db
    (Printf.sprintf "delete from tags where id = '%s';\n" tag);
  Alcotest.(check int)
    "the plant_tags row went with its tag" 0
    (List.length (rows db "select id from plant_tags;\n"))

let position_checks () =
  let db = migrated_db () in
  let check name = "CHECK constraint failed: observations_" ^ name in
  let obs n = Printf.sprintf "00000000-0000-4000-8000-0000000000%02d" n in
  accepted "lat and lon together" db
    (observation_sql ~lat:"48.5" ~lon:"7.5" ~accuracy:"0" (obs 1));
  accepted "no position at all" db (observation_sql (obs 2));
  rejected "lat without lon"
    ~because:(check "position_both_or_neither")
    db
    (observation_sql ~lat:"48.5" (obs 3));
  rejected "lon without lat"
    ~because:(check "position_both_or_neither")
    db
    (observation_sql ~lon:"7.5" (obs 4));
  rejected "accuracy without a position"
    ~because:(check "accuracy_needs_position")
    db
    (observation_sql ~accuracy:"10" (obs 5));
  accepted "lat at exactly 90 and lon at -180" db
    (observation_sql ~lat:"90" ~lon:"-180" (obs 6));
  rejected "lat above 90" ~because:(check "lat_range") db
    (observation_sql ~lat:"90.5" ~lon:"0" (obs 7));
  rejected "lon below -180" ~because:(check "lon_range") db
    (observation_sql ~lat:"0" ~lon:"-180.5" (obs 8));
  accepted "lat at exactly -90 and lon at 180" db
    (observation_sql ~lat:"-90" ~lon:"180" (obs 10));
  rejected "lat below -90" ~because:(check "lat_range") db
    (observation_sql ~lat:"-90.5" ~lon:"0" (obs 11));
  rejected "lon above 180" ~because:(check "lon_range") db
    (observation_sql ~lat:"0" ~lon:"180.5" (obs 12));
  rejected "a negative accuracy"
    ~because:(check "accuracy_nonnegative")
    db
    (observation_sql ~lat:"0" ~lon:"0" ~accuracy:"-1" (obs 9))

let natural_keys () =
  let db = migrated_db () in
  let tag = "00000000-0000-4000-8000-0000000000c1" in
  accepted "a plant, a tag and one link" db
    (plant_sql plant_a
    ^ tag_sql tag
    ^ plant_tag_sql "00000000-0000-4000-8000-0000000000d1" ~plant:plant_a ~tag);
  rejected "a second plant_tags row for the same pair"
    ~because:"UNIQUE constraint failed: plant_tags.plant_id, plant_tags.tag_id"
    db
    (plant_tag_sql "00000000-0000-4000-8000-0000000000d2" ~plant:plant_a ~tag);
  accepted "a GBIF ref" db
    (plant_ref_sql "00000000-0000-4000-8000-0000000000e1" ~plant:plant_a
       ~source:Source.Gbif);
  rejected "a second GBIF ref for the same plant"
    ~because:"UNIQUE constraint failed: plant_refs.plant_id, plant_refs.source"
    db
    (plant_ref_sql "00000000-0000-4000-8000-0000000000e2" ~plant:plant_a
       ~source:Source.Gbif);
  accepted "a Wikidata ref for the same plant" db
    (plant_ref_sql "00000000-0000-4000-8000-0000000000e3" ~plant:plant_a
       ~source:Source.Wikidata);
  accepted "a GBIF reference row" db
    (reference_sql "00000000-0000-4000-8000-0000000000b1" ~plant:plant_a
       ~source:Source.Gbif);
  rejected "a second reference row for the same plant and source"
    ~because:"UNIQUE constraint failed: reference.plant_id, reference.source" db
    (reference_sql "00000000-0000-4000-8000-0000000000b2" ~plant:plant_a
       ~source:Source.Gbif)

(* ---------- lookup tables ---------- *)

(* A migration never changes after release, so the values are literal in the
   SQL; this is what catches a constructor added without a migration. *)
let lookup_values () =
  let db = migrated_db () in
  List.iter
    (fun (table, expected) ->
      Alcotest.(check (list string))
        (Printf.sprintf "%s holds the to_string of every constructor" table)
        (List.sort String.compare expected)
        (List.map (string_field "value")
           (rows db
              (Printf.sprintf "select value from %s order by value;\n" table))))
    lookup_tables

let lookup_value_not_null () =
  let db = migrated_db () in
  List.iter
    (fun (table, _) ->
      rejected
        (Printf.sprintf "a null value in %s" table)
        ~because:"NOT NULL constraint failed" db
        (Printf.sprintf "insert into %s (value) values (null);\n" table))
    lookup_tables

(* Each value column, given a label its lookup table does not hold in place of
   the fixture's valid one. *)
let unknown_values () =
  let db = migrated_db () in
  let obs = "00000000-0000-4000-8000-000000000001" in
  let relabel ~from ~to_ sql =
    replace_all ~sub:("'" ^ from ^ "'") ~by:("'" ^ to_ ^ "'") sql
  in
  accepted "a plant and an observation" db
    (plant_sql plant_a ^ observation_sql ~plant:(quoted plant_a) obs);
  rejected "a photo whose original_target is unknown"
    ~because:"FOREIGN KEY constraint failed" db
    (relabel ~from:"drive" ~to_:"dropbox"
       (photo_sql "00000000-0000-4000-8000-0000000000f1" ~observation:obs));
  rejected "a photo whose upload_state is unknown"
    ~because:"FOREIGN KEY constraint failed" db
    (relabel ~from:"pending" ~to_:"local_only"
       (photo_sql "00000000-0000-4000-8000-0000000000f2" ~observation:obs));
  rejected "a plant_refs row whose source is unknown"
    ~because:"FOREIGN KEY constraint failed" db
    (relabel ~from:"gbif" ~to_:"flickr"
       (plant_ref_sql "00000000-0000-4000-8000-0000000000e1" ~plant:plant_a
          ~source:Source.Gbif));
  rejected "a reference row whose source is unknown"
    ~because:"FOREIGN KEY constraint failed" db
    (relabel ~from:"gbif" ~to_:"flickr"
       (reference_sql "00000000-0000-4000-8000-0000000000b1" ~plant:plant_a
          ~source:Source.Gbif));
  rejected "a reference row whose status is unknown"
    ~because:"FOREIGN KEY constraint failed" db
    (relabel ~from:"complete" ~to_:"ok"
       (reference_sql "00000000-0000-4000-8000-0000000000b2" ~plant:plant_a
          ~source:Source.Gbif));
  rejected "a label in another case" ~because:"FOREIGN KEY constraint failed" db
    (relabel ~from:"pending" ~to_:"Pending"
       (photo_sql "00000000-0000-4000-8000-0000000000f3" ~observation:obs))

let outbox_defaults () =
  let db = migrated_db () in
  accepted "two outbox rows without seq nor attempts" db
    (Printf.sprintf
       "insert into outbox (table_name, row_id, op, payload_json, created_at) \
        values ('plants', '%s', 'upsert', '{}', %s);\n\
        insert into outbox (table_name, row_id, op, payload_json, created_at) \
        values ('plants', '%s', 'upsert', '{}', %s);\n"
       plant_a t0 plant_b t0);
  let got = rows db "select seq, attempts from outbox order by seq;\n" in
  Alcotest.(check (list int))
    "seq is assigned in insertion order" [1; 2]
    (List.map (int_field "seq") got);
  Alcotest.(check (list int))
    "attempts defaults to 0" [0; 0]
    (List.map (int_field "attempts") got)

(* ---------- fixtures ---------- *)

let time s =
  match Ptime.of_rfc3339 s with
  | Ok (t, _, _) -> t
  | Error _ -> invalid_arg ("fixture time " ^ s)

let some_or_fail what = function
  | Some v -> v
  | None -> invalid_arg ("fixture " ^ what)

let plant_id s = some_or_fail s (Ids.Plant_id.of_string s)
let photo_id s = some_or_fail s (Ids.Photo_id.of_string s)

type local

let flag : (local, bool, [`Mandatory]) Col.t =
  {ty = Not_Null Bool; name = "flag"}

let ratio : (local, float, [`Mandatory]) Col.t =
  {ty = Not_Null Numeric; name = "ratio"}

let moment : (local, Ptime.t, [`Mandatory]) Col.t =
  {ty = Not_Null TimestampTz; name = "t"}

(* ---------- Codec.param ---------- *)

let check_param what expected actual = Alcotest.check param what expected actual

let param_integer () =
  check_param "Integer 7 is Int 7" (Int 7) (Codec.param Tables.Photos.width 7);
  check_param "Integer 0 is Int 0" (Int 0) (Codec.param Tables.Photos.height 0);
  check_param "Nullable Integer Some 7 is Int 7" (Int 7)
    (Codec.param P.gbif_key (Some 7));
  check_param "Nullable Integer None is Null" Null (Codec.param P.gbif_key None)

let param_numeric () =
  check_param "Numeric 1.5 is Float 1.5" (Float 1.5) (Codec.param ratio 1.5);
  check_param "Numeric -0.25 is Float -0.25" (Float (-0.25))
    (Codec.param ratio (-0.25));
  check_param "Nullable Numeric Some 48. is Float 48." (Float 48.)
    (Codec.param Tables.Observations.lat (Some 48.));
  check_param "Nullable Numeric None is Null" Null
    (Codec.param Tables.Observations.lat None)

let param_bool () =
  check_param "Bool true is Int 1" (Int 1) (Codec.param flag true);
  check_param "Bool false is Int 0" (Int 0) (Codec.param flag false)

let param_str () =
  check_param "Str is Text, verbatim"
    (Text "Rose 'Albertine', \"grimpant\" -- é")
    (Codec.param P.display_name "Rose 'Albertine', \"grimpant\" -- é");
  check_param "Str empty is Text empty" (Text "") (Codec.param P.notes "");
  check_param "Nullable Str None is Null" Null (Codec.param P.authorship None)

let param_custom () =
  check_param "a plant id is Text of its lowercase form"
    (Text "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d")
    (Codec.param P.id (plant_id "0A1B2C3D-4E5F-4A6B-8C7D-9E0F1A2B3C4D"));
  check_param "upload_state is Text of its label" (Text "original_missing")
    (Codec.param Tables.Photos.upload_state Photo.Upload_state.Original_missing);
  check_param "Nullable Custom Some is Text"
    (Text "00000000-0000-4000-8000-000000000001")
    (Codec.param P.cover_photo_id
       (Some (photo_id "00000000-0000-4000-8000-000000000001")));
  check_param "Nullable Custom None is Null" Null
    (Codec.param P.cover_photo_id None)

let text_codec () =
  let c =
    Codec.text ~name:"flag" ~to_string:string_of_bool ~of_string:(function
      | "true" -> Some true
      | _ -> None)
  in
  let json = Alcotest.testable Yojson.Safe.pp Yojson.Safe.equal in
  Alcotest.(check json)
    "to_json is a JSON string" (`String "false") (c.to_json false);
  Alcotest.(check (option bool))
    "of_json reads a JSON string" (Some true)
    (c.of_json (`String "true"));
  Alcotest.(check (option bool))
    "of_json rejects a JSON bool" None
    (c.of_json (`Bool true));
  Alcotest.(check (option bool))
    "of_json rejects an unknown string" None
    (c.of_json (`String "yes"))

let param_json () =
  check_param "JSON [\"a\"] is Text [\"a\"]" (Text "[\"a\"]")
    (Codec.param P.aliases (`List [`String "a"]));
  check_param "JSON [] is Text []" (Text "[]")
    (Codec.param P.aliases (`List []));
  check_param "JSON object is Text of its compact form" (Text "{\"k\":1}")
    (Codec.param Tables.Reference.payload (`Assoc [("k", `Int 1)]))

let param_timestamp () =
  check_param "TimestampTz is Text in the fixed UTC microsecond form"
    (Text "2026-10-28T12:00:05.123456Z")
    (Codec.param P.created_at (time "2026-10-28T14:00:05.123456+02:00"));
  check_param "Nullable TimestampTz Some is Text"
    (Text "2026-10-28T12:00:05.000000Z")
    (Codec.param P.deleted_at (Some (time "2026-10-28T12:00:05Z")));
  check_param "Nullable TimestampTz None is Null" Null
    (Codec.param P.deleted_at None)

(* ---------- Codec.timestamp ---------- *)

let timestamp_whole_second () =
  let s = Codec.timestamp (time "2026-10-28T12:00:05Z") in
  Alcotest.(check string)
    "a whole second has six zero digits" "2026-10-28T12:00:05.000000Z" s;
  Alcotest.(check int) "it is 27 characters" 27 (String.length s)

let timestamp_offset () =
  Alcotest.(check string)
    "an offset is moved to UTC" "2026-10-28T10:30:00.500000Z"
    (Codec.timestamp (time "2026-10-28T12:30:00.5+02:00"))

let timestamp_truncates () =
  let t = time "2026-10-28T12:00:05.123456789Z" in
  let s = Codec.timestamp t in
  Alcotest.(check string)
    "nanoseconds are truncated, not rounded" "2026-10-28T12:00:05.123456Z" s;
  let back =
    Codec.decode ~json:[] (Row.col moment)
      (Yojson.Safe.to_string (`Assoc [("t", `String s)]))
  in
  Alcotest.(check (result ptime codec_error))
    "it decodes to the microsecond truncation"
    (Ok (Ptime.truncate ~frac_s:6 t))
    back

let timestamp_order () =
  let sample =
    List.map time
      [
        "1969-12-31T23:59:59.999999Z";
        "1970-01-01T00:00:00Z";
        "2026-10-28T12:00:05Z";
        "2026-10-28T12:00:05.1Z";
        "2026-10-28T12:00:05.000001Z";
        "2026-10-28T12:00:05.999999Z";
        "2026-10-28T12:00:06Z";
        "2026-10-28T23:59:59.5+02:00";
        "2026-10-29T00:00:00Z";
        "2100-01-01T00:00:00Z";
      ]
  in
  let sign n = compare n 0 in
  List.iter
    (fun a ->
      List.iter
        (fun b ->
          Alcotest.(check int)
            (Printf.sprintf "text order of %s and %s is time order"
               (Ptime.to_rfc3339 a) (Ptime.to_rfc3339 b))
            (sign (Ptime.compare a b))
            (sign (String.compare (Codec.timestamp a) (Codec.timestamp b))))
        sample)
    sample

(* ---------- Codec.decode ---------- *)

let check_decode what expected actual =
  Alcotest.(check (result yojson codec_error)) what expected actual

let decode_not_json () =
  match Codec.decode ~json:[] (Row.col P.notes) "nope" with
  | Error (Invalid_row _) -> ()
  | Ok _ -> Alcotest.fail "a text that is not JSON gives Invalid_row, not Ok"
  | Error e ->
      Alcotest.failf "a text that is not JSON gives Invalid_row, not %s"
        (string_of_codec_error e)

let decode_not_object () =
  Alcotest.(check (result string codec_error))
    "a JSON array is not a row" (Error (Invalid_row "not an object"))
    (Codec.decode ~json:[] (Row.col P.notes) "[1]")

let decode_bad_json_column () =
  check_decode "a json column holding invalid JSON text names the column"
    (Error (Invalid_json_column "aliases"))
    (Codec.decode
       ~json:[Codec.json P.aliases]
       (Row.col P.aliases) {|{"aliases": "["}|})

let decode_json_text () =
  check_decode "a json column's text is parsed"
    (Ok (`List [`String "a"; `String "é"]))
    (Codec.decode
       ~json:[Codec.json P.aliases]
       (Row.col P.aliases) {|{"aliases": "[\"a\",\"é\"]"}|})

let decode_json_already_parsed () =
  check_decode "a json column already holding an array is left as is"
    (Ok (`List [`String "a"]))
    (Codec.decode
       ~json:[Codec.json P.aliases]
       (Row.col P.aliases) {|{"aliases": ["a"]}|})

let decode_json_default () =
  check_decode "with ~json:[] the text stays a string"
    (Ok (`String "[\"a\"]"))
    (Codec.decode ~json:[] (Row.col P.aliases) {|{"aliases": "[\"a\"]"}|})

let decode_other_column_untouched () =
  Alcotest.(check (result string codec_error))
    "a column not listed in ~json keeps its JSON-looking text" (Ok "[1]")
    (Codec.decode
       ~json:[Codec.json P.aliases]
       (Row.col P.display_name) {|{"display_name": "[1]", "aliases": "[]"}|})

(* A table with two JSON columns, as a join of plants and reference would
   select. *)
type two_json

let json_a : (two_json, Yojson.Safe.t, [`Mandatory]) Col.t =
  {ty = Not_Null JSON; name = "a"}

let json_b : (two_json, Yojson.Safe.t, [`Mandatory]) Col.t =
  {ty = Not_Null JSON; name = "b"}

let two_json_spec : (two_json, Yojson.Safe.t * Yojson.Safe.t) Row.t =
  let open Row.Syntax in
  let+ a = Row.col json_a and+ b = Row.col json_b in
  (a, b)

let decode_two_json_columns () =
  let decode = Codec.decode ~json:[Codec.json json_a; Codec.json json_b] in
  Alcotest.(check (result (pair yojson yojson) codec_error))
    "both json columns are parsed"
    (Ok (`List [`Int 1], `Assoc []))
    (decode two_json_spec {|{"a": "[1]", "b": "{}"}|});
  Alcotest.(check (result (pair yojson yojson) codec_error))
    "the bad one of two json columns is named" (Error (Invalid_json_column "b"))
    (decode two_json_spec {|{"a": "[1]", "b": "{"}|})

let decode_json_key_absent () =
  Alcotest.(check (result string codec_error))
    "a ~json key absent from the row is ignored" (Ok "x")
    (Codec.decode
       ~json:[Codec.json P.aliases]
       (Row.col P.display_name) {|{"display_name": "x"}|})

let decode_missing () =
  Alcotest.(check (result string codec_error))
    "a missing column is Row Missing" (Error (Row `Missing))
    (Codec.decode ~json:[] (Row.col P.display_name) {|{}|})

let decode_null_json () =
  check_decode "null in a not-null json column is Row UnexpectedNull"
    (Error (Row `UnexpectedNull))
    (Codec.decode
       ~json:[Codec.json P.aliases]
       (Row.col P.aliases) {|{"aliases": null}|})

let decode_int_overflow () =
  Alcotest.(check (result (option int) codec_error))
    "an integer literal out of range is Row WrongType, not an exception"
    (Error (Row `WrongType))
    (Codec.decode ~json:[] (Row.col P.gbif_key)
       {|{"gbif_key": 99999999999999999999}|})

let decode_int_as_numeric () =
  Alcotest.(check (result (option (float 0.)) codec_error))
    "a JSON int in a Numeric column is a float" (Ok (Some 48.))
    (Codec.decode ~json:[] (Row.col Tables.Observations.lat) {|{"lat": 48}|})

let parser_error () =
  match Codec.decode ~json:[] (Row.col P.notes) "nope" with
  | Error e -> e
  | Ok _ -> Alcotest.fail "decoding \"nope\" succeeded"

let error_strings () =
  List.iter
    (fun e ->
      let s = Codec.error_to_string e in
      Alcotest.(check bool)
        (Printf.sprintf "error_to_string of %s is not empty"
           (string_of_codec_error e))
        true (s <> "");
      Alcotest.(check bool)
        (Printf.sprintf "error_to_string of %s is one line"
           (string_of_codec_error e))
        false (String.contains s '\n'))
    [
      parser_error ();
      Codec.Invalid_row "line 1:\nunexpected";
      Invalid_row "not an object";
      Invalid_json_column "aliases";
      Row `Missing;
      Row `NotAnObject;
      Row `WrongType;
      Row `UnexpectedNull;
      Row `DummyRow;
    ];
  Alcotest.(check bool)
    "error_to_string of Invalid_json_column names the column" true
    (contains ~sub:"aliases"
       (Codec.error_to_string (Invalid_json_column "aliases")))

(* ---------- plants round-trip ---------- *)

type plant_row = {
  id : Ids.Plant_id.t;
  display_name : string;
  aliases : Yojson.Safe.t;
  scientific_name : string option;
  authorship : string option;
  gbif_key : int option;
  notes : string;
  notes_updated_at : Ptime.t option;
  cover_photo_id : Ids.Photo_id.t option;
  created_at : Ptime.t;
  updated_at : Ptime.t;
  deleted_at : Ptime.t option;
}

let plants_spec : (Tables.plants, plant_row) Row.t =
  let open Row.Syntax in
  let+ id = Row.col P.id
  and+ display_name = Row.col P.display_name
  and+ aliases = Row.col P.aliases
  and+ scientific_name = Row.col P.scientific_name
  and+ authorship = Row.col P.authorship
  and+ gbif_key = Row.col P.gbif_key
  and+ notes = Row.col P.notes
  and+ notes_updated_at = Row.col P.notes_updated_at
  and+ cover_photo_id = Row.col P.cover_photo_id
  and+ created_at = Row.col P.created_at
  and+ updated_at = Row.col P.updated_at
  and+ deleted_at = Row.col P.deleted_at in
  {
    id;
    display_name;
    aliases;
    scientific_name;
    authorship;
    gbif_key;
    notes;
    notes_updated_at;
    cover_photo_id;
    created_at;
    updated_at;
    deleted_at;
  }

let plant_params (r : plant_row) : (string * Codec.param) list =
  [
    (name P.id, Codec.param P.id r.id);
    (name P.display_name, Codec.param P.display_name r.display_name);
    (name P.aliases, Codec.param P.aliases r.aliases);
    (name P.scientific_name, Codec.param P.scientific_name r.scientific_name);
    (name P.authorship, Codec.param P.authorship r.authorship);
    (name P.gbif_key, Codec.param P.gbif_key r.gbif_key);
    (name P.notes, Codec.param P.notes r.notes);
    (name P.notes_updated_at, Codec.param P.notes_updated_at r.notes_updated_at);
    (name P.cover_photo_id, Codec.param P.cover_photo_id r.cover_photo_id);
    (name P.created_at, Codec.param P.created_at r.created_at);
    (name P.updated_at, Codec.param P.updated_at r.updated_at);
    (name P.deleted_at, Codec.param P.deleted_at r.deleted_at);
  ]

let plant_row_json (r : plant_row) =
  let t x = `String (Ptime.to_rfc3339 ~frac_s:12 ~tz_offset_s:0 x) in
  let opt f = function None -> `Null | Some v -> f v in
  let str s = `String s in
  `Assoc
    [
      ("id", str (Ids.Plant_id.to_string r.id));
      ("display_name", str r.display_name);
      ("aliases", r.aliases);
      ("scientific_name", opt str r.scientific_name);
      ("authorship", opt str r.authorship);
      ("gbif_key", opt (fun n -> `Int n) r.gbif_key);
      ("notes", str r.notes);
      ("notes_updated_at", opt t r.notes_updated_at);
      ( "cover_photo_id",
        opt (fun p -> str (Ids.Photo_id.to_string p)) r.cover_photo_id );
      ("created_at", t r.created_at);
      ("updated_at", t r.updated_at);
      ("deleted_at", opt t r.deleted_at);
    ]

let plant_row =
  Alcotest.testable
    (fun f r ->
      Format.pp_print_string f (Yojson.Safe.to_string (plant_row_json r)))
    (fun a b -> Yojson.Safe.equal (plant_row_json a) (plant_row_json b))

let bare_plant =
  {
    id = plant_id "00000000-0000-4000-8000-000000000001";
    display_name = "Pissenlit";
    aliases = `List [];
    scientific_name = None;
    authorship = None;
    gbif_key = None;
    notes = "";
    notes_updated_at = None;
    cover_photo_id = None;
    created_at = time "2026-10-28T12:00:05.000001Z";
    updated_at = time "2026-10-28T12:00:05.000001Z";
    deleted_at = None;
  }

let full_plant =
  {
    id = plant_id "00000000-0000-4000-8000-000000000002";
    display_name = "Rose 'Albertine', \"grimpant\"";
    aliases = `List [`String "Églantier"; `String "dog rose"];
    scientific_name = Some "Rosa canina";
    authorship = Some "L.";
    gbif_key = Some 8395064;
    notes = "Ligne 1;\nligne 2 -- pas un commentaire";
    notes_updated_at = Some (time "2026-10-28T14:00:05.123456+02:00");
    cover_photo_id = Some (photo_id "00000000-0000-4000-8000-0000000000ff");
    created_at = time "2026-01-01T00:00:00Z";
    updated_at = time "2026-10-28T12:00:05.999999Z";
    deleted_at = Some (time "2026-10-28T12:00:06.5Z");
  }

let insert_plant_sql r =
  let params = plant_params r in
  Printf.sprintf "insert into plants (%s) values (%s);\n"
    (String.concat ", " (List.map fst params))
    (String.concat ", " (List.map (fun (_, p) -> sql_literal p) params))

let plants_round_trip () =
  let db = migrated_db () in
  exec_ok "inserting two plants" db
    (insert_plant_sql full_plant ^ insert_plant_sql bare_plant);
  let stored = rows db "select * from plants order by id;\n" in
  Alcotest.(check (list string))
    "aliases is stored as JSON text"
    ["[]"; "[\"Églantier\",\"dog rose\"]"]
    (List.map (string_field (name P.aliases)) stored);
  Alcotest.(check (list (result plant_row codec_error)))
    "both rows read back equal to what was written"
    [Ok bare_plant; Ok full_plant]
    (List.map
       (fun row ->
         Codec.decode
           ~json:[Codec.json P.aliases]
           plants_spec
           (Yojson.Safe.to_string row))
       stored)

(* ---------- runner ---------- *)

let () =
  let case name f = Alcotest.test_case name `Quick f in
  Alcotest.run "store"
    [
      ( "Schema",
        [
          case "migration versions are 1..n and latest is the last"
            versions_ascending;
          case "pending from 0 is every migration" pending_from_zero;
          case "pending at latest is empty" pending_at_latest;
          case "pending from 1 is migrations 2 and 3" pending_from_one;
          case "pending from 2 is migration 3" pending_from_two;
          case "pending above latest is Unknown_version" pending_above_latest;
          case "pending below 0 is Unknown_version" pending_negative;
          case "batch is the statements then the user_version pragma"
            batch_appends_version;
        ] );
      ( "Schema in sqlite3",
        [
          case
            "a fresh install reaches the latest version with sixteen tables, \
             the search table and its triggers"
            fresh_install;
          case "an empty database upgrades to the latest version"
            upgrade_from_empty;
          case "a version 1 database upgrades to the latest version"
            upgrade_from_version_1;
          case "a version 2 database upgrades to 3 and keeps its rows"
            upgrade_from_version_2_keeps_rows;
          case "each statement string is one SQL statement"
            one_statement_per_string;
          case "no column is named sql_deleted or last_modified"
            no_plugin_reserved_columns;
          case "tables have the columns of Tables and of the local tables"
            columns;
          case "not null columns are exactly the Not_Null ones" nullability;
          case "column types are the local types of Tables' columns" types;
          case "the foreign-key indexes exist" indexes;
          case "foreign keys hold except on plants.cover_photo_id" foreign_keys;
          case "deleting a plant or a tag cascades to its children"
            delete_cascades;
          case "observation position checks mirror the server" position_checks;
          case "plant_tags, plant_refs and reference natural keys are unique"
            natural_keys;
          case "outbox seq is assigned and attempts defaults to 0"
            outbox_defaults;
        ] );
      ( "Lookup tables in sqlite3",
        [
          case "each lookup table holds every constructor's to_string"
            lookup_values;
          case "a lookup value cannot be null" lookup_value_not_null;
          case "an unknown value is rejected by its foreign key" unknown_values;
        ] );
      ( "Codec.param",
        [
          case "Integer is Int, None is Null" param_integer;
          case "Numeric is Float" param_numeric;
          case "Bool is Int 1 or 0" param_bool;
          case "Str is Text verbatim" param_str;
          case "Custom is Text of its string" param_custom;
          case "text builds a JSON-string Custom codec" text_codec;
          case "JSON is Text of its compact form" param_json;
          case "TimestampTz is Text in UTC microseconds" param_timestamp;
        ] );
      ( "Codec.timestamp",
        [
          case "a whole second is 27 characters ending in Z"
            timestamp_whole_second;
          case "an offset is rendered in UTC" timestamp_offset;
          case "sub-microsecond digits are truncated" timestamp_truncates;
          case "text order is time order" timestamp_order;
        ] );
      ( "Codec.decode",
        [
          case "text that is not JSON is Invalid_row" decode_not_json;
          case "a JSON array is Invalid_row not an object" decode_not_object;
          case "invalid JSON text in a json column is Invalid_json_column"
            decode_bad_json_column;
          case "JSON text in a json column is parsed" decode_json_text;
          case "an already parsed json column is left alone"
            decode_json_already_parsed;
          case "with ~json:[], JSON text stays a string" decode_json_default;
          case "a column outside ~json is never parsed"
            decode_other_column_untouched;
          case "a ~json key absent from the row is ignored"
            decode_json_key_absent;
          case "two json columns are both parsed" decode_two_json_columns;
          case "a missing column is Row Missing" decode_missing;
          case "null in a not-null json column is Row UnexpectedNull"
            decode_null_json;
          case "an out-of-range integer is Row WrongType" decode_int_overflow;
          case "a JSON int decodes in a Numeric column" decode_int_as_numeric;
          case "error_to_string is one non-empty line" error_strings;
        ] );
      ( "plants round-trip",
        [
          case "two plants rows round-trip through SQL and the codec"
            plants_round_trip;
        ] );
    ]
