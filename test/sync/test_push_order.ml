module F = Sync_fixtures
module Cli = Sqlite_cli

let t0 = F.time "2026-11-01T09:00:00Z"
let t1 = F.time "2026-11-01T09:01:00Z"
let t3 = F.time "2026-11-01T09:03:00Z"

(* ---------- four edits, as the UI makes them ---------- *)

let seed () =
  let db = Cli.migrated_db () in
  let p = F.plant ~at:t0 1 "Thym" in
  let o = F.observation ~at:t0 ~plant:1 1 in
  let f = F.photo ~at:t0 ~observation:1 1 in
  let g = F.tag ~at:t0 1 "Aromatique" in
  let (_ : int) =
    Cli.edit_ok "edit 1: new plant, observation, photo" db
      [Plants.upsert p; Observations.upsert o; Photos.upsert f]
  in
  let (_ : int) =
    Cli.edit_ok "edit 2: a tag and the plant-tag link" db
      [Tags.upsert g; Tags.tag ~plant:p.id ~tag:g.id ~at:t1]
  in
  let renamed = {p with display_name = "Thym renomme"} in
  let (_ : int) =
    Cli.edit_ok "edit 3: the plant renamed" db [Plants.upsert renamed]
  in
  let (_ : int) =
    Cli.edit_ok "edit 4: Cascade.observation on O" db
      (Cascade.observation ~at:t3 ~photos:[f.id] o.id)
  in
  (db, p, renamed)

let body_of (r : Mock_http.request) =
  match r.body with
  | Some b -> Yojson.Safe.from_string b
  | None -> Alcotest.fail "no body"

let string_field name j =
  match j with
  | `Assoc kvs -> (
      match List.assoc_opt name kvs with
      | Some (`String s) -> s
      | _ ->
          Alcotest.failf "no string field %s in %s" name
            (Yojson.Safe.to_string j))
  | j -> Alcotest.failf "not an object: %s" (Yojson.Safe.to_string j)

let string_field_opt name j =
  match j with
  | `Assoc kvs -> (
      match List.assoc_opt name kvs with
      | Some (`String s) -> Some s
      | _ -> None)
  | _ -> None

(* Reads every entry Outbox.next gives, in seq order, and pushes each in
   that order over Mock_http (every push answered 201). Returns the
   entries and the requests sent, both in push order. *)
let push_all db =
  Mock_http.reset ();
  Mock_http.respond ~status:201 "";
  let entries = Cli.all db (Outbox.next ~limit:100) in
  List.iter
    (fun (e : Outbox.entry) ->
      match F.R.push F.conn ~table_name:e.table_name ~payload:e.payload with
      | Ok () -> ()
      | Error _ -> Alcotest.failf "push of %s/%s failed" e.table_name e.row_id)
    entries;
  (entries, List.rev !Mock_http.requests)

let expected_table_order =
  [
    "plants";
    "observations";
    "photos";
    "tags";
    "plant_tags";
    "plants";
    "photos";
    "observations";
  ]

let push_order_matches_the_outbox_s_order () =
  let db, p, renamed = seed () in
  let entries, requests = push_all db in
  Alcotest.(check (list string))
    "Outbox.next's table_name, in seq order" expected_table_order
    (List.map (fun (e : Outbox.entry) -> e.table_name) entries);
  Alcotest.(check (list string))
    "the pushed targets, in push order"
    (List.map (fun t -> "/rest/v1/" ^ t) expected_table_order)
    (List.map
       (fun (r : Mock_http.request) -> Mock_http.decoded_target r.url)
       requests);
  let plants_requests =
    List.filter
      (fun (r : Mock_http.request) ->
        String.equal (Mock_http.decoded_target r.url) "/rest/v1/plants")
      requests
  in
  match plants_requests with
  | [first; second] ->
      Alcotest.(check string)
        "the first plants request has the original name" p.display_name
        (string_field "display_name" (body_of first));
      Alcotest.(check string)
        "the second plants request has the new name (no coalescing)"
        renamed.display_name
        (string_field "display_name" (body_of second))
  | rs ->
      Alcotest.failf "expected exactly 2 plants requests, got %d"
        (List.length rs)

let json = Alcotest.testable Yojson.Safe.pp Yojson.Safe.equal

let every_request_body_equals_its_entry_s_payload () =
  let db, _, _ = seed () in
  let entries, requests = push_all db in
  List.iter2
    (fun (e : Outbox.entry) (r : Mock_http.request) ->
      Alcotest.check json
        (Printf.sprintf "%s/%s: request body = entry payload" e.table_name
           e.row_id)
        e.payload (body_of r))
    entries requests

(* The foreign-key columns of each table, read back from the pushed body.
   The test also compares the (table, column) pairs it found a value for
   with the seed's, so that a renamed column fails instead of checking
   nothing. *)
let foreign_key_columns = function
  | "observations" -> ["plant_id"]
  | "photos" -> ["observation_id"]
  | "plant_tags" -> ["plant_id"; "tag_id"]
  | "plant_refs" | "reference" -> ["plant_id"]
  | "plants" | "tags" -> []
  | other -> Alcotest.failf "unknown table %s in the outbox" other

let foreign_keys (e : Outbox.entry) body =
  List.filter_map
    (fun column ->
      Option.map
        (fun id -> ((e.table_name, column), id))
        (string_field_opt column body))
    (foreign_key_columns e.table_name)

let parents_pushed_before_their_children () =
  let db, _, _ = seed () in
  let entries, requests = push_all db in
  let _pushed, checked =
    List.fold_left2
      (fun (pushed, checked) (e : Outbox.entry) (r : Mock_http.request) ->
        let body = body_of r in
        let fks = foreign_keys e body in
        List.iter
          (fun ((_, column), fk) ->
            Alcotest.(check bool)
              (Printf.sprintf "%s/%s: its %s %s was pushed earlier" e.table_name
                 e.row_id column fk)
              true (List.mem fk pushed))
          fks;
        (string_field "id" body :: pushed, List.map fst fks @ checked))
      ([], []) entries requests
  in
  Alcotest.(check (list (pair string string)))
    "the foreign keys checked"
    [
      ("observations", "plant_id");
      ("photos", "observation_id");
      ("plant_tags", "plant_id");
      ("plant_tags", "tag_id");
    ]
    (List.sort_uniq compare checked)

(* Parks a middle entry (the tag) and compares by seq, so that two entries
   of the same table cannot stand in for each other. *)
let a_parked_entry_is_absent_and_the_rest_s_order_is_unchanged () =
  let db, _, _ = seed () in
  let before = Cli.all db (Outbox.next ~limit:100) in
  let parked =
    match
      List.find_opt
        (fun (e : Outbox.entry) -> String.equal e.table_name "tags")
        before
    with
    | Some e -> e
    | None -> Alcotest.fail "no tags entry in the outbox"
  in
  let (_ : int) =
    Cli.write_ok "park" db (Outbox.park parked.seq ~error:"409 conflict")
  in
  let after = Cli.all db (Outbox.next ~limit:100) in
  let seqs = List.map (fun (e : Outbox.entry) -> Outbox.seq_to_int e.seq) in
  Alcotest.(check (list int))
    "the parked entry is gone, the rest keep their order"
    (List.filter
       (fun s -> not (Int.equal s (Outbox.seq_to_int parked.seq)))
       (seqs before))
    (seqs after)

let tests =
  [
    ( "the pushed order equals Outbox.next's order; two plants requests, no \
       coalescing",
      `Quick,
      push_order_matches_the_outbox_s_order );
    ( "every request's body is structurally equal to its entry's payload",
      `Quick,
      every_request_body_equals_its_entry_s_payload );
    ( "every row with a foreign key is pushed after the row it points to",
      `Quick,
      parents_pushed_before_their_children );
    ( "a parked entry is absent from Outbox.next; the rest keep their order",
      `Quick,
      a_parked_entry_is_absent_and_the_rest_s_order_is_unchanged );
  ]
