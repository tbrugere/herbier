(* A [Local.S] over the sqlite3 CLI (test/store/sqlite_cli.ml, copied in),
   standing in for the device's [Herbier_store_io.Db] (local.mli): [t] is a
   migrated db file's path.

   [bare_transaction] mirrors [Db.bare_transaction]'s contract (local.mli):
   atomic, foreign keys deferred to the commit, rolled back on any error.
   Every [Tx.write] / [Tx.write_local] is buffered as inlined SQL text (the
   CLI cannot bind, as test/store's [inline]) rather than run; only once [f]
   returns [Ok] does the whole buffer run as one sqlite3 process, under
   [-bail], as one script:
     pragma foreign_keys = on; begin; pragma defer_foreign_keys = on;
     <buffered statements…> commit;
   A failing statement, including a deferred foreign key at ["commit"],
   stops sqlite3 under [-bail] with the transaction open, so nothing is
   applied ([Db]'s rollback); an [Error] from [f] runs nothing. So a write
   error mid-transaction is only ever seen at the script, never by the
   [Tx.write] that buffered it: pull's error branch after [Tx.write] is not
   exercised here, its commit-time path is.

   Buffered writes are invisible to [Tx.all] until the script runs;
   pull.mli's "never reads back its own writes" keeps this faithful. *)

module Stmt = Herbier_store.Stmt
module Outbox = Herbier_store.Outbox
module IO = Mock_http.IO
module Cli = Sqlite_cli

type t = string
type error = string

let error_to_string = Fun.id

(* Folds Sqlite_cli.all_results' per-row decode results into one Result
   instead of failing the test outright, so a real decode error reaches
   push/pull as a store error, the way Db.all's would. *)
let collect results =
  let rec go acc = function
    | [] -> Ok (List.rev acc)
    | Ok v :: rest -> go (v :: acc) rest
    | Error e :: _ -> Error (Cli.string_of_codec_error e)
  in
  go [] results

let all db q = collect (Cli.all_results db q)
let write db s = Cli.write db s

type tx = {db : string; buf : Buffer.t}

module Tx = struct
  let all (tx : tx) q = all tx.db q

  (* The count is unknown until the script runs; pull.ml, the only caller,
     discards it. *)
  let write (tx : tx) (b : Outbox.bare) =
    Buffer.add_string tx.buf (Cli.inline (Outbox.bare_stmt b));
    Ok 1

  let write_local (tx : tx) (s : Stmt.t) =
    Buffer.add_string tx.buf (Cli.inline s);
    Ok 1
end

let bare_transaction db f =
  let tx = {db; buf = Buffer.create 256} in
  match f tx with
  | Error _ as e -> e
  | Ok _ as ok -> (
      let script =
        "pragma foreign_keys = on;\nbegin;\npragma defer_foreign_keys = on;\n"
        ^ Buffer.contents tx.buf
        ^ "commit;\n"
      in
      match Cli.sqlite db script with
      | Ok (_ : string) -> ok
      | Error stderr -> Error stderr)

(* conn () is awaited once per request by Push.run and Pull.run; wrapping it
   counts how many times it actually ran, for "conn is called exactly once
   per request" checks. *)
let counting_conn conn =
  let calls = ref 0 in
  ( (fun () ->
      incr calls;
      conn ()),
    calls )
