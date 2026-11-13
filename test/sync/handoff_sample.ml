(* Prints the fixed hand-off test/runner/test_keepalive.mjs reads: a session
   doc (Wire.session_doc) and a queue doc of 3 outbox entries
   (Wire.queue_doc, one per table: plants, tags, observations), each
   still JSON text so the node test does not need to touch OCaml's JSON
   rendering. The 3 entries are built through the real sqlite3 CLI
   (Outbox.entry_stmt + Outbox.next): Outbox.seq is abstract, so there is no
   other way to get a real [Outbox.entry]. Needs SQLITE3 on the environment
   (set by test/runner/dune, as the other sync tests set it for `dune test`).

   Not an alcotest binary: on any failure this just prints to stderr and
   exits 1, which fails the dune rule that runs it. *)

module Session = Herbier_sync_core.Auth.Session
module Synced = Herbier_sync_core.Synced
module Keepalive = Herbier_sync_core.Keepalive
module Outbox = Herbier_store.Outbox
module F = Sync_fixtures
module Wire = Keepalive.Wire

let t = F.time "2026-11-12T10:00:00Z"
let db = Sqlite_cli.migrated_db ()

let () =
  List.iter
    (fun stmt -> ignore (Sqlite_cli.write_ok "handoff entry" db stmt : int))
    [
      F.entry_stmt Synced.plants (F.plant ~at:t 1 "Digitale");
      F.entry_stmt Synced.tags (F.tag ~at:t 1 "Vivace");
      F.entry_stmt Synced.observations (F.observation ~at:t 1);
    ]

let entries = Sqlite_cli.all db (Outbox.next ~limit:3)

let () =
  match List.length entries with
  | 3 -> ()
  | n ->
      Printf.eprintf "handoff_sample: expected 3 outbox entries, got %d\n" n;
      exit 1

(* supabase_url matches test/sync/test_keepalive.ml's;
   test/runner/test_keepalive.mjs reads these through handoff.json. *)
let supabase_url = "http://127.0.0.1:54321"
let apikey = "handoff-anon-key"

let session : Session.t =
  {
    access_token = "handoff-access-token";
    refresh_token = "handoff-refresh-token";
    expires_at = t;
    user_id = "00000000-0000-7000-8000-000000000001";
    email = Some "job@herbier.local";
  }

let session_json = Wire.session_doc ~supabase_url ~apikey session

let {Wire.doc = queue_json; skipped; _} =
  Wire.queue_doc ~supabase_url ~apikey entries

let () =
  match skipped with
  | None -> ()
  | Some _ ->
      prerr_endline "handoff_sample: unexpected skipped entry";
      exit 1

let () =
  let out =
    `Assoc
      [
        ("supabase_url", `String supabase_url);
        ("apikey", `String apikey);
        ("session_doc_json", `String session_json);
        ("queue_doc_json", `String queue_json);
      ]
  in
  print_string (Yojson.Safe.to_string out)
