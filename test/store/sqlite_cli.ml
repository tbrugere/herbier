(* Helpers shared by test_store, test_queries and test_outbox: the sqlite3
   CLI as a stand-in for the Capacitor plugin (one process per call,
   parameters inlined by position since the CLI cannot bind), migrations
   applied as Db.open_ applies them, and the testables of the codec's types.
   A test that needs the CLI, or FTS5 in it, fails when they are absent rather
   than skipping, so the search checks cannot pass without running. *)

(* ---------- small string helpers ---------- *)

let rec find_from ~sub s i =
  let n = String.length sub in
  match i + n > String.length s with
  | true -> None
  | false -> (
      match String.sub s i n = sub with
      | true -> Some i
      | false -> find_from ~sub s (i + 1))

let contains ~sub s = Option.is_some (find_from ~sub s 0)

let split_on ~sep s =
  let rec go i acc =
    match find_from ~sub:sep s i with
    | None -> List.rev (String.sub s i (String.length s - i) :: acc)
    | Some j -> go (j + String.length sep) (String.sub s i (j - i) :: acc)
  in
  go 0 []

let replace_all ~sub ~by s = String.concat by (split_on ~sep:sub s)

let rstrip s =
  let rec last i =
    match i >= 0 && String.contains " \t\r\n" s.[i] with
    | true -> last (i - 1)
    | false -> i
  in
  String.sub s 0 (last (String.length s - 1) + 1)

(* ---------- temp files ---------- *)

let read_file path = In_channel.with_open_bin path In_channel.input_all

(* style: one module-level list because the at_exit hook below must reach
   every temp file of the run, whichever test made it. *)
let temp_files = ref []

let temp_file suffix =
  let path = Filename.temp_file "herbier_store_" suffix in
  temp_files := path :: !temp_files;
  path

let () =
  at_exit (fun () ->
      List.iter
        (fun p ->
          match Sys.file_exists p with true -> Sys.remove p | false -> ())
        !temp_files)

(* A path with no file behind it. *)
let absent_path () =
  let path = temp_file ".db" in
  Sys.remove path;
  path

(* ---------- the sqlite3 CLI ---------- *)

let sqlite3 : string option Lazy.t =
  lazy
    (let exe =
       match Sys.getenv_opt "SQLITE3" with
       | Some p when p <> "" -> p
       | Some _ | None -> "sqlite3"
     in
     let code =
       Sys.command
         (Filename.quote_command exe ~stdout:Filename.null ~stderr:Filename.null
            ["-version"])
     in
     match code with 0 -> Some exe | _ -> None)

(* Runs [sql] on [db] with [exe] in one process (one connection), stopping at
   the first error: [Ok stdout] or [Error stderr]. *)
let run_cli exe ~json db sql =
  let input = temp_file ".sql" in
  let out = temp_file ".out" in
  let err = temp_file ".err" in
  Out_channel.with_open_bin input (fun oc -> Out_channel.output_string oc sql);
  let flags = match json with true -> ["-json"] | false -> [] in
  let code =
    Sys.command
      (Filename.quote_command exe ~stdin:input ~stdout:out ~stderr:err
         (["-bail"; "-batch"] @ flags @ [db]))
  in
  match code with 0 -> Ok (read_file out) | _ -> Error (read_file err)

(* Migration 2 creates an FTS5 table with this tokenizer. [Error] carries the
   CLI's stderr, which says why (no fts5 module, or something else). *)
let fts5 : (unit, string) result Lazy.t =
  lazy
    (match Lazy.force sqlite3 with
    | None -> Error "sqlite3 not found"
    | Some exe ->
        Result.map
          (fun (_ : string) -> ())
          (run_cli exe ~json:false (absent_path ())
             "create virtual table probe using fts5(x, tokenize = 'unicode61 \
              remove_diacritics 2');\n"))

let require_sqlite3 () =
  match Lazy.force sqlite3 with
  | Some exe -> exe
  | None -> Alcotest.fail "sqlite3 not found (set SQLITE3 or put it on PATH)"

let require_fts5 () =
  match Lazy.force fts5 with
  | Ok () -> ()
  | Error stderr ->
      Alcotest.failf
        "creating an FTS5 table with unicode61 remove_diacritics 2, which \
         migration 2 needs, failed: %s"
        stderr

(* A database path with no file behind it; fails the test when the CLI
   cannot run the migrations. *)
let fresh_db () =
  let (_ : string) = require_sqlite3 () in
  require_fts5 ();
  absent_path ()

let sqlite ?(json = false) db sql = run_cli (require_sqlite3 ()) ~json db sql

let exec_ok what db sql =
  match sqlite db sql with
  | Ok _ -> ()
  | Error e -> Alcotest.failf "%s: sqlite3 failed: %s" what e

(* Rows of a SELECT, as sqlite3 -json prints them (empty output: no row). *)
let rows db sql : Yojson.Safe.t list =
  match sqlite ~json:true db sql with
  | Error e -> Alcotest.failf "query %S failed: %s" sql e
  | Ok out -> (
      match String.trim out with
      | "" -> []
      | text -> (
          match Yojson.Safe.from_string text with
          | `List rows -> rows
          | other ->
              Alcotest.failf "sqlite3 -json printed %s"
                (Yojson.Safe.to_string other)
          | exception Yojson.Json_error m ->
              Alcotest.failf "query %S printed %S: %s" sql out m))

let field name (row : Yojson.Safe.t) =
  match row with
  | `Assoc kvs -> (
      match List.assoc_opt name kvs with
      | Some v -> v
      | None ->
          Alcotest.failf "no column %s in %s" name (Yojson.Safe.to_string row))
  | other -> Alcotest.failf "not a row: %s" (Yojson.Safe.to_string other)

let string_field name row =
  match field name row with
  | `String s -> s
  | other ->
      Alcotest.failf "column %s is %s, not text" name
        (Yojson.Safe.to_string other)

let int_field name row =
  match field name row with
  | `Int n -> n
  | other ->
      Alcotest.failf "column %s is %s, not an integer" name
        (Yojson.Safe.to_string other)

let user_version db =
  match rows db "pragma user_version;\n" with
  | [row] -> int_field "user_version" row
  | _ -> Alcotest.fail "pragma user_version gave no single row"

let names_of db sql = List.map (string_field "name") (rows db sql)

(* Ordinary tables, without SQLite's own and without the FTS5 table and its
   shadow tables (plant_search, plant_search_data, …). *)
let table_names db =
  names_of db
    "select name from sqlite_master where type = 'table' and name not like \
     'sqlite_%' and name not like 'plant\\_search%' escape '\\' order by name;\n"

let trigger_names db =
  names_of db
    "select name from sqlite_master where type = 'trigger' order by name;\n"

let column_names db table =
  List.sort String.compare
    (names_of db (Printf.sprintf "pragma table_info(%s);\n" table))

let count db sql =
  match rows db sql with
  | [row] -> int_field "n" row
  | _ -> Alcotest.failf "%S gave no single row" sql

(* ---------- parameters ---------- *)

(* The CLI cannot bind, so parameters are inlined. *)
let sql_literal : Codec.param -> string = function
  | Null -> "NULL"
  | Int n -> string_of_int n
  | Float f -> Printf.sprintf "%.17g" f
  | Text s -> "'" ^ replace_all ~sub:"'" ~by:"''" s ^ "'"

(* [s] as one SQL text ending in ";\n", each [?] outside a string literal
   replaced by the next parameter. Fails when the number of [?] is not the
   number of parameters (Stmt.t's invariant). *)
let inline (s : Stmt.t) =
  let n = String.length s.sql in
  let b = Buffer.create (n + 64) in
  let rec go i quoted (params : Codec.param list) =
    match (i < n, params) with
    | false, [] -> ()
    | false, _ :: _ ->
        Alcotest.failf "%d parameter(s) more than '?' in %S"
          (List.length params) s.sql
    | true, _ -> (
        match (s.sql.[i], quoted, params) with
        | '\'', _, _ ->
            Buffer.add_char b '\'';
            go (i + 1) (not quoted) params
        | '?', false, p :: rest ->
            Buffer.add_string b (sql_literal p);
            go (i + 1) false rest
        | '?', false, [] ->
            Alcotest.failf "more '?' than parameters in %S" s.sql
        | c, _, _ ->
            Buffer.add_char b c;
            go (i + 1) quoted params)
  in
  go 0 false s.params;
  let text = rstrip (Buffer.contents b) in
  match String.ends_with ~suffix:";" text with
  | true -> text ^ "\n"
  | false -> text ^ ";\n"

(* ---------- Stmt through the CLI, as Db runs it on the device ---------- *)

(* Db.open_ enables foreign keys on the device; the CLI starts with them
   off. *)
let fk_on = "pragma foreign_keys = on;\n"

(* Db.write: [Ok changes] or [Error stderr]. changes() counts the rows the
   statement itself changed, not those its triggers changed. The plugin's run
   reports a total_changes() difference, which includes the rows changed by
   triggers (the FTS triggers of migration 2 on plants), so exact counts can
   differ on the device; "changes > 0" means the same on both sides, since a
   statement that changes no row fires no trigger. *)
let write db (s : Stmt.t) =
  match
    sqlite ~json:true db (fk_on ^ inline s ^ "select changes() as n;\n")
  with
  | Error e -> Error e
  | Ok out -> (
      match Yojson.Safe.from_string (String.trim out) with
      | `List [`Assoc [("n", `Int n)]] -> Ok n
      | other ->
          Alcotest.failf "select changes() printed %s"
            (Yojson.Safe.to_string other)
      | exception Yojson.Json_error m ->
          Alcotest.failf "select changes() printed %S: %s" out m)

let write_ok what db s =
  match write db s with
  | Ok n -> n
  | Error e -> Alcotest.failf "%s: %S failed: %s" what s.sql e

let write_all_ok what db stmts =
  List.iter (fun s -> ignore (write_ok what db s : int)) stmts

(* One statement per CLI call, no transaction: only its SQL is under test. *)
let write_bare db (b : Outbox.bare) = write db (Outbox.bare_stmt b)

let write_bare_ok what db b =
  match write_bare db b with
  | Ok n -> n
  | Error e -> Alcotest.failf "%s: bare write failed: %s" what e

let write_all_bare_ok what db bares =
  List.iter (fun b -> ignore (write_bare_ok what db b : int)) bares

(* Every outbox row as sqlite3 -json prints it, in seq order. *)
let outbox db = rows db "select * from outbox order by seq;\n"
let outbox_count db = count db "select count(*) as n from outbox;\n"

(* Db.edit without the transaction, one CLI process per statement: the edits
   before a failing one stay written. *)
let edit db edits =
  let rec go appended = function
    | [] -> Ok appended
    | e :: rest -> (
        match write_bare db (Outbox.without_entry e) with
        | Error err -> Error err
        | Ok 0 -> go appended rest
        | Ok _ -> (
            let reread = Outbox.reread e in
            match rows db (inline reread) with
            | [row] -> (
                match Outbox.append e (Yojson.Safe.to_string row) with
                | Error err ->
                    Alcotest.failf "Outbox.append on the row of %S: %s"
                      reread.sql
                      (Codec.error_to_string err)
                | Ok s -> (
                    match write db s with
                    | Error err -> Error err
                    | Ok _ -> go (appended + 1) rest))
            | got ->
                Alcotest.failf "read-back %S gave %d rows, expected one"
                  reread.sql (List.length got)))
  in
  go 0 edits

let edit_ok what db edits =
  match edit db edits with
  | Ok n -> n
  | Error err -> Alcotest.failf "%s: an edit failed: %s" what err

let string_of_row_error : Postgrest.Row.error -> string = function
  | `Missing -> "Missing"
  | `NotAnObject -> "NotAnObject"
  | `WrongType -> "WrongType"
  | `UnexpectedNull -> "UnexpectedNull"
  | `DummyRow -> "DummyRow"

let string_of_codec_error : Codec.error -> string = function
  | Invalid_row m -> Printf.sprintf "Invalid_row %S" m
  | Invalid_json_column c -> Printf.sprintf "Invalid_json_column %S" c
  | Row e -> "Row " ^ string_of_row_error e

(* Db.all, keeping each row's decoding result. *)
let all_results db q =
  List.map
    (fun row -> Stmt.decode q (Yojson.Safe.to_string row))
    (rows db (inline (Stmt.stmt q)))

(* Db.all: every row decoded, or the test fails on the first that does not. *)
let all db q =
  List.map
    (function
      | Ok v -> v
      | Error e ->
          Alcotest.failf "decoding a row of %S: %s" (Stmt.stmt q).sql
            (string_of_codec_error e))
    (all_results db q)

(* Db.find: 0 or 1 row; more fails the test. *)
let find_result db q =
  match all_results db q with
  | [] -> Ok None
  | [Ok v] -> Ok (Some v)
  | [Error e] -> Error e
  | _ :: _ :: _ as more ->
      Alcotest.failf "%S returned %d rows, expected at most one"
        (Stmt.stmt q).sql (List.length more)

let find db q =
  match find_result db q with
  | Ok v -> v
  | Error e ->
      Alcotest.failf "decoding the row of %S: %s" (Stmt.stmt q).sql
        (string_of_codec_error e)

(* ---------- migrated databases ---------- *)

let pending_or_fail current =
  match Schema.pending ~current with
  | Ok ms -> ms
  | Error (Schema.Unknown_version {found; latest}) ->
      Alcotest.failf
        "pending ~current:%d: Unknown_version {found = %d; latest = %d}" current
        found latest

(* The text sqlite3 runs for one executeSet of [statements]: each string
   followed by its own ";" line (a string may end in a -- comment), all in one
   transaction. *)
let batch_text statements =
  "begin;\n"
  ^ String.concat "" (List.map (fun s -> s ^ "\n;\n") statements)
  ^ "commit;\n"

(* Applies [ms] the way Db.open_ does it: one transaction per migration, its
   Schema.batch. *)
let apply_migrations db ms =
  List.iter
    (fun (m : Schema.migration) ->
      exec_ok
        (Printf.sprintf "migration %d" m.version)
        db
        (batch_text (Schema.batch m)))
    ms

let migrate db ~current = apply_migrations db (pending_or_fail current)

let migrated_db () =
  let db = fresh_db () in
  migrate db ~current:0;
  db

(* ---------- testables ---------- *)

let string_of_param : Codec.param -> string = function
  | Null -> "Null"
  | Int n -> Printf.sprintf "Int %d" n
  | Float f -> Printf.sprintf "Float %.17g" f
  | Text s -> Printf.sprintf "Text %S" s

let equal_param (a : Codec.param) (b : Codec.param) =
  match (a, b) with
  | Null, Null -> true
  | Int a, Int b -> Int.equal a b
  | Float a, Float b -> Float.equal a b
  | Text a, Text b -> String.equal a b
  | (Null | Int _ | Float _ | Text _), _ -> false

let param =
  Alcotest.testable
    (fun f p -> Format.pp_print_string f (string_of_param p))
    equal_param

let codec_error =
  Alcotest.testable
    (fun f e -> Format.pp_print_string f (string_of_codec_error e))
    (fun a b ->
      String.equal (string_of_codec_error a) (string_of_codec_error b))

let yojson =
  Alcotest.testable
    (fun f j -> Format.pp_print_string f (Yojson.Safe.to_string j))
    Yojson.Safe.equal

let ptime =
  Alcotest.testable
    (fun f t ->
      Format.pp_print_string f (Ptime.to_rfc3339 ~frac_s:12 ~tz_offset_s:0 t))
    Ptime.equal

(* A testable through a JSON rendering, so diffs are readable. *)
let testable_of_json to_json =
  Alcotest.testable
    (fun f x -> Format.pp_print_string f (Yojson.Safe.to_string (to_json x)))
    (fun a b -> Yojson.Safe.equal (to_json a) (to_json b))
