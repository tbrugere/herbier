(* Native checks of app/store/references.ml (queries and edits on
   [reference] and [plant_refs]), through the sqlite3 CLI exactly as
   test_outbox.ml checks Tags: Cli.edit runs each edit as Db.edit does on
   the device (statement, read-back, appended entry), without the
   transaction. The JSON column through the Capacitor plugin is a device
   check (#dev/store, "references" group). *)

module Ids = Herbier_domain.Ids
module Plant = Herbier_domain.Plant
module Reference = Herbier_domain.Reference
module Source = Herbier_domain.Reference.Source
module Status = Herbier_domain.Reference.Status
module Col = Postgrest.Col
module Input = Postgrest.Input
module Cli = Sqlite_cli

(* ---------- fixtures ---------- *)

let time s =
  match Ptime.of_rfc3339 s with
  | Ok (t, _, _) -> t
  | Error _ -> invalid_arg ("fixture time " ^ s)

let uuid n = Printf.sprintf "00000000-0000-4000-8000-%012x" n

let id_of what of_string n =
  match of_string (uuid n) with
  | Some x -> x
  | None -> invalid_arg ("fixture " ^ what)

let plant_id = id_of "plant id" Ids.Plant_id.of_string
let reference_id = id_of "reference id" Ids.Reference_id.of_string
let plant_ref_id = id_of "plant ref id" Ids.Plant_ref_id.of_string
let t1 = time "2026-10-28T12:00:00Z"
let t2 = time "2026-10-28T14:00:02.5+02:00"
let t3 = time "2026-10-28T12:00:03.999999Z"

let plant n display_name : Plant.t =
  {
    id = plant_id n;
    display_name;
    aliases = [];
    scientific_name = None;
    authorship = None;
    gbif_key = None;
    notes = "";
    notes_updated_at = None;
    cover_photo_id = None;
    created_at = t1;
    updated_at = t1;
    deleted_at = None;
  }

let derived_reference_id ~plant ~source =
  Ids.Reference_id.of_key ~plant ~source:(Source.to_string source)

let derived_plant_ref_id ~plant ~source =
  Ids.Plant_ref_id.of_key ~plant ~source:(Source.to_string source)

(* A payload with a nested object, an array, a unicode string and an int
   above 2^31 (jsoo's limit, not native's: the native round trip is the
   subject here; the jsoo boundary is checked in test/refs/jsoo/smoke.ml and
   the #dev/store device check). *)
let payload_a : Yojson.Safe.t =
  `Assoc
    [
      ( "species",
        `Assoc
          [
            ("key", `Int 5414995);
            ("scientificName", `String "Digitalis purpurea L.");
          ] );
      ( "vernacular_names",
        `Assoc
          [
            ( "results",
              `List
                [
                  `Assoc
                    [
                      ("vernacularName", `String "Digitale pourprée");
                      ("language", `String "fra");
                    ];
                ] );
          ] );
      ("occurrence_count", `Int 5_110_295_086);
    ]

let payload_b : Yojson.Safe.t =
  `Assoc [("summary", `Assoc [("title", `String "Arnica des montagnes")])]

(* ---------- raw outbox rows, as in test_outbox.ml ---------- *)

type raw = {table_name : string; row_id : string; payload : Yojson.Safe.t}

let raw_of_row row =
  let payload_text = Cli.string_field "payload_json" row in
  let payload =
    match Yojson.Safe.from_string payload_text with
    | j -> j
    | exception Yojson.Json_error m ->
        Alcotest.failf "payload_json %S is not JSON: %s" payload_text m
  in
  {
    table_name = Cli.string_field "table_name" row;
    row_id = Cli.string_field "row_id" row;
    payload;
  }

let outbox db = List.map raw_of_row (Cli.outbox db)

let last db =
  match List.rev (outbox db) with
  | r :: _ -> r
  | [] -> Alcotest.fail "the outbox is empty"

let check_edit what expected db edits =
  Alcotest.(check int) what expected (Cli.edit_ok what db edits)

(* ---------- hand-built PostgREST bodies, as in test_outbox.ml ---------- *)

let ts_json t = Col.to_json (Not_Null TimestampTz) t
let ts_opt_json t = Col.to_json (Nullable TimestampTz) t
let str s = `String s

let reference_payload ~id ~plant ~source ~fetched_at ~payload ~status
    ~created_at ~updated_at ~deleted_at : Yojson.Safe.t =
  `Assoc
    [
      ("id", str id);
      ("plant_id", str (Ids.Plant_id.to_string plant));
      ("source", str (Source.to_string source));
      ("fetched_at", ts_json fetched_at);
      ("payload", payload);
      ("status", str (Status.to_string status));
      ("created_at", ts_json created_at);
      ("updated_at", ts_json updated_at);
      ("deleted_at", ts_opt_json deleted_at);
    ]

let plant_ref_payload ~id ~plant ~source ~external_id ~url ~created_at
    ~updated_at ~deleted_at : Yojson.Safe.t =
  `Assoc
    [
      ("id", str id);
      ("plant_id", str (Ids.Plant_id.to_string plant));
      ("source", str (Source.to_string source));
      ("external_id", str external_id);
      ("url", str url);
      ("created_at", ts_json created_at);
      ("updated_at", ts_json updated_at);
      ("deleted_at", ts_opt_json deleted_at);
    ]

(* ---------- put: new row, revisit, pulled row, revive ---------- *)

let put_new_row () =
  let db = Cli.migrated_db () in
  let p = plant 0x1 "Digitale" in
  let (_ : int) =
    Cli.write_ok "seed plant" db (Outbox.without_entry (Plants.upsert p))
  in
  check_edit "put appends 1 entry" 1 db
    [
      References.put ~plant:p.id ~source:Source.Gbif ~fetched_at:t1
        ~payload:payload_a ~status:Status.Complete ~at:t1;
    ];
  let id = derived_reference_id ~plant:p.id ~source:Source.Gbif in
  let entry = last db in
  Alcotest.(check string) "table_name" "reference" entry.table_name;
  Alcotest.(check string)
    "row_id is the derived id"
    (Ids.Reference_id.to_string id)
    entry.row_id;
  Alcotest.(check Cli.yojson)
    "the entry's payload"
    (reference_payload
       ~id:(Ids.Reference_id.to_string id)
       ~plant:p.id ~source:Source.Gbif ~fetched_at:t1 ~payload:payload_a
       ~status:Status.Complete ~created_at:t1 ~updated_at:t1 ~deleted_at:None)
    entry.payload;
  match Cli.find db (References.get p.id Source.Gbif) with
  | Some (r : Reference.t) ->
      Alcotest.(check Cli.yojson)
        "payload reads back structurally equal to what was written" payload_a
        r.payload
  | None -> Alcotest.fail "get found no row"

let put_again_updates () =
  let db = Cli.migrated_db () in
  let p = plant 0x1 "Digitale" in
  let (_ : int) =
    Cli.write_ok "seed plant" db (Outbox.without_entry (Plants.upsert p))
  in
  check_edit "first put appends 1 entry" 1 db
    [
      References.put ~plant:p.id ~source:Source.Gbif ~fetched_at:t1
        ~payload:payload_a ~status:Status.Complete ~at:t1;
    ];
  check_edit "second put appends 1 entry" 1 db
    [
      References.put ~plant:p.id ~source:Source.Gbif ~fetched_at:t2
        ~payload:payload_b ~status:Status.Partial ~at:t2;
    ];
  let id = derived_reference_id ~plant:p.id ~source:Source.Gbif in
  Alcotest.(check Cli.yojson)
    "the second entry's payload"
    (reference_payload
       ~id:(Ids.Reference_id.to_string id)
       ~plant:p.id ~source:Source.Gbif ~fetched_at:t2 ~payload:payload_b
       ~status:Status.Partial ~created_at:t1 ~updated_at:t2 ~deleted_at:None)
    (last db).payload;
  match Cli.find db (References.get p.id Source.Gbif) with
  | Some (r : Reference.t) -> (
      Alcotest.(check Cli.yojson) "payload" payload_b r.payload;
      match r.status with
      | Status.Partial -> ()
      | Status.Complete | Status.Missing | Status.Failed ->
          Alcotest.failf "status: expected Partial, got %s"
            (Status.to_string r.status))
  | None -> Alcotest.fail "get found no row"

let put_over_a_pulled_row_keeps_its_id () =
  let db = Cli.migrated_db () in
  let p = plant 0x1 "Digitale" in
  let (_ : int) =
    Cli.write_ok "seed plant" db (Outbox.without_entry (Plants.upsert p))
  in
  let stored = reference_id 0xd1 in
  let pulled : Reference.t =
    {
      id = stored;
      plant_id = p.id;
      source = Source.Gbif;
      fetched_at = t1;
      payload = `Assoc [];
      status = Status.Complete;
      created_at = t1;
      updated_at = t1;
      deleted_at = None;
    }
  in
  let (_ : int) =
    Cli.write_ok "a pulled reference" db
      (Stmt.upsert ~table:Tables.Reference.table (References.input pulled))
  in
  check_edit "put over the pulled row appends 1 entry" 1 db
    [
      References.put ~plant:p.id ~source:Source.Gbif ~fetched_at:t2
        ~payload:payload_a ~status:Status.Partial ~at:t2;
    ];
  let entry = last db in
  Alcotest.(check string)
    "the entry's row_id is the stored id, not of_key" (uuid 0xd1) entry.row_id;
  match Cli.find db (References.get p.id Source.Gbif) with
  | Some (r : Reference.t) ->
      Alcotest.(check string)
        "id kept" (uuid 0xd1)
        (Ids.Reference_id.to_string r.id);
      Alcotest.(check string)
        "created_at kept" (Codec.timestamp t1)
        (Codec.timestamp r.created_at)
  | None -> Alcotest.fail "get found no row"

let put_revives_a_soft_deleted_row () =
  let db = Cli.migrated_db () in
  let p = plant 0x1 "Digitale" in
  let (_ : int) =
    Cli.write_ok "seed plant" db (Outbox.without_entry (Plants.upsert p))
  in
  let id = derived_reference_id ~plant:p.id ~source:Source.Gbif in
  let deleted : Reference.t =
    {
      id;
      plant_id = p.id;
      source = Source.Gbif;
      fetched_at = t1;
      payload = payload_a;
      status = Status.Complete;
      created_at = t1;
      updated_at = t1;
      deleted_at = Some t1;
    }
  in
  let (_ : int) =
    Cli.write_ok "a soft-deleted reference, set by hand" db
      (Stmt.upsert ~table:Tables.Reference.table (References.input deleted))
  in
  (match Cli.all db (References.get p.id Source.Gbif) with
  | [] -> ()
  | _ -> Alcotest.fail "the soft-deleted row should not be live yet");
  check_edit "put revives it" 1 db
    [
      References.put ~plant:p.id ~source:Source.Gbif ~fetched_at:t2
        ~payload:payload_b ~status:Status.Complete ~at:t2;
    ];
  Alcotest.(check Cli.yojson)
    "the entry carries the kept id and created_at, deleted_at null"
    (reference_payload
       ~id:(Ids.Reference_id.to_string id)
       ~plant:p.id ~source:Source.Gbif ~fetched_at:t2 ~payload:payload_b
       ~status:Status.Complete ~created_at:t1 ~updated_at:t2 ~deleted_at:None)
    (last db).payload;
  match Cli.find db (References.get p.id Source.Gbif) with
  | Some (r : Reference.t) ->
      Alcotest.(check bool)
        "deleted_at is null" true
        (Option.is_none r.deleted_at)
  | None -> Alcotest.fail "the revived row should be live"

(* ---------- of_plant, get ---------- *)

let of_plant_orders_filters_live_and_by_plant () =
  let db = Cli.migrated_db () in
  let p1 = plant 0x1 "Digitale" and p2 = plant 0x2 "Arnica" in
  let (_ : int) =
    Cli.write_ok "seed p1" db (Outbox.without_entry (Plants.upsert p1))
  in
  let (_ : int) =
    Cli.write_ok "seed p2" db (Outbox.without_entry (Plants.upsert p2))
  in
  check_edit "p1 gbif" 1 db
    [
      References.put ~plant:p1.id ~source:Source.Gbif ~fetched_at:t1
        ~payload:payload_a ~status:Status.Complete ~at:t1;
    ];
  check_edit "p1 wikipedia" 1 db
    [
      References.put ~plant:p1.id ~source:Source.Wikipedia ~fetched_at:t1
        ~payload:payload_b ~status:Status.Complete ~at:t1;
    ];
  check_edit "p2 gbif" 1 db
    [
      References.put ~plant:p2.id ~source:Source.Gbif ~fetched_at:t1
        ~payload:payload_a ~status:Status.Complete ~at:t1;
    ];
  let soft_deleted : Reference.t =
    {
      id = derived_reference_id ~plant:p1.id ~source:Source.Plantnet;
      plant_id = p1.id;
      source = Source.Plantnet;
      fetched_at = t1;
      payload = `Assoc [];
      status = Status.Complete;
      created_at = t1;
      updated_at = t1;
      deleted_at = Some t1;
    }
  in
  let (_ : int) =
    Cli.write_ok "a soft-deleted plantnet row for p1" db
      (Stmt.upsert ~table:Tables.Reference.table
         (References.input soft_deleted))
  in
  (match Cli.all db (References.of_plant p1.id) with
  | [(a : Reference.t); (b : Reference.t)] ->
      Alcotest.(check string)
        "first is gbif (label order)" "gbif"
        (Source.to_string a.source);
      Alcotest.(check string)
        "second is wikipedia" "wikipedia"
        (Source.to_string b.source)
  | refs ->
      Alcotest.failf
        "expected 2 live rows for p1 (soft-deleted and other plant excluded), \
         got %d"
        (List.length refs));
  match Cli.all db (References.get p1.id Source.Plantnet) with
  | [] -> ()
  | _ -> Alcotest.fail "get on an absent/soft-deleted row should give 0 rows"

let put_for_unknown_plant_fails () =
  let db = Cli.migrated_db () in
  match
    Cli.edit db
      [
        References.put ~plant:(plant_id 0x99) ~source:Source.Gbif ~fetched_at:t1
          ~payload:payload_a ~status:Status.Complete ~at:t1;
      ]
  with
  | Ok n ->
      Alcotest.failf "a reference for an unknown plant should fail, appended %d"
        n
  | Error stderr ->
      Alcotest.(check bool)
        "it fails on the foreign key" true
        (Cli.contains ~sub:"FOREIGN KEY constraint failed" stderr)

(* ---------- remove ---------- *)

let remove_live_row_soft_deletes () =
  let db = Cli.migrated_db () in
  let p = plant 0x1 "Digitale" in
  let (_ : int) =
    Cli.write_ok "seed plant" db (Outbox.without_entry (Plants.upsert p))
  in
  check_edit "put appends 1 entry" 1 db
    [
      References.put ~plant:p.id ~source:Source.Gbif ~fetched_at:t1
        ~payload:payload_a ~status:Status.Complete ~at:t1;
    ];
  let id = derived_reference_id ~plant:p.id ~source:Source.Gbif in
  check_edit "remove on the live row appends 1 entry" 1 db
    [References.remove ~plant:p.id ~source:Source.Gbif ~at:t2];
  Alcotest.(check Cli.yojson)
    "the entry: deleted_at = updated_at = at, id and payload kept"
    (reference_payload
       ~id:(Ids.Reference_id.to_string id)
       ~plant:p.id ~source:Source.Gbif ~fetched_at:t1 ~payload:payload_a
       ~status:Status.Complete ~created_at:t1 ~updated_at:t2
       ~deleted_at:(Some t2))
    (last db).payload;
  match Cli.all db (References.get p.id Source.Gbif) with
  | [] -> ()
  | _ -> Alcotest.fail "the removed row should no longer be live"

let remove_no_row_or_already_deleted_is_a_no_op () =
  let db = Cli.migrated_db () in
  let p = plant 0x1 "Digitale" in
  let (_ : int) =
    Cli.write_ok "seed plant" db (Outbox.without_entry (Plants.upsert p))
  in
  check_edit "remove on a missing row appends nothing" 0 db
    [References.remove ~plant:p.id ~source:Source.Gbif ~at:t1];
  check_edit "put appends 1 entry" 1 db
    [
      References.put ~plant:p.id ~source:Source.Gbif ~fetched_at:t1
        ~payload:payload_a ~status:Status.Complete ~at:t1;
    ];
  check_edit "first remove appends 1 entry" 1 db
    [References.remove ~plant:p.id ~source:Source.Gbif ~at:t2];
  check_edit "remove again appends nothing" 0 db
    [References.remove ~plant:p.id ~source:Source.Gbif ~at:t3]

let put_after_remove_revives () =
  let db = Cli.migrated_db () in
  let p = plant 0x1 "Digitale" in
  let (_ : int) =
    Cli.write_ok "seed plant" db (Outbox.without_entry (Plants.upsert p))
  in
  let id = derived_reference_id ~plant:p.id ~source:Source.Gbif in
  check_edit "put appends 1 entry" 1 db
    [
      References.put ~plant:p.id ~source:Source.Gbif ~fetched_at:t1
        ~payload:payload_a ~status:Status.Complete ~at:t1;
    ];
  check_edit "remove appends 1 entry" 1 db
    [References.remove ~plant:p.id ~source:Source.Gbif ~at:t2];
  check_edit "put after remove revives it" 1 db
    [
      References.put ~plant:p.id ~source:Source.Gbif ~fetched_at:t3
        ~payload:payload_b ~status:Status.Complete ~at:t3;
    ];
  match Cli.find db (References.get p.id Source.Gbif) with
  | Some (r : Reference.t) ->
      Alcotest.(check string)
        "id kept"
        (Ids.Reference_id.to_string id)
        (Ids.Reference_id.to_string r.id);
      Alcotest.(check bool)
        "deleted_at is null" true
        (Option.is_none r.deleted_at)
  | None -> Alcotest.fail "the revived row should be live"

let remove_another_source_untouched () =
  let db = Cli.migrated_db () in
  let p = plant 0x1 "Digitale" in
  let (_ : int) =
    Cli.write_ok "seed plant" db (Outbox.without_entry (Plants.upsert p))
  in
  check_edit "gbif" 1 db
    [
      References.put ~plant:p.id ~source:Source.Gbif ~fetched_at:t1
        ~payload:payload_a ~status:Status.Complete ~at:t1;
    ];
  check_edit "wikipedia" 1 db
    [
      References.put ~plant:p.id ~source:Source.Wikipedia ~fetched_at:t1
        ~payload:payload_b ~status:Status.Complete ~at:t1;
    ];
  check_edit "remove gbif only" 1 db
    [References.remove ~plant:p.id ~source:Source.Gbif ~at:t2];
  match Cli.all db (References.get p.id Source.Wikipedia) with
  | [(r : Reference.t)] ->
      Alcotest.(check bool)
        "wikipedia still live" true
        (Option.is_none r.deleted_at)
  | rs ->
      Alcotest.failf "expected 1 live wikipedia row, got %d" (List.length rs)

(* ---------- link, unlink, plant_refs ---------- *)

let link_unlink_and_plant_refs () =
  let db = Cli.migrated_db () in
  let p = plant 0x1 "Digitale" in
  let (_ : int) =
    Cli.write_ok "seed plant" db (Outbox.without_entry (Plants.upsert p))
  in
  let gbif_id = derived_plant_ref_id ~plant:p.id ~source:Source.Gbif in
  let gbif_id_str = Ids.Plant_ref_id.to_string gbif_id in
  check_edit "link on a missing row appends 1 entry" 1 db
    [
      References.link ~plant:p.id ~source:Source.Gbif ~external_id:"1"
        ~url:"https://www.gbif.org/species/1" ~at:t1;
    ];
  Alcotest.(check Cli.yojson)
    "the new link's entry"
    (plant_ref_payload ~id:gbif_id_str ~plant:p.id ~source:Source.Gbif
       ~external_id:"1" ~url:"https://www.gbif.org/species/1" ~created_at:t1
       ~updated_at:t1 ~deleted_at:None)
    (last db).payload;
  check_edit "link with the same values appends nothing" 0 db
    [
      References.link ~plant:p.id ~source:Source.Gbif ~external_id:"1"
        ~url:"https://www.gbif.org/species/1" ~at:t2;
    ];
  check_edit "link with another url appends 1 entry" 1 db
    [
      References.link ~plant:p.id ~source:Source.Gbif ~external_id:"1"
        ~url:"https://www.gbif.org/species/1-updated" ~at:t2;
    ];
  Alcotest.(check Cli.yojson)
    "the updated link's entry"
    (plant_ref_payload ~id:gbif_id_str ~plant:p.id ~source:Source.Gbif
       ~external_id:"1" ~url:"https://www.gbif.org/species/1-updated"
       ~created_at:t1 ~updated_at:t2 ~deleted_at:None)
    (last db).payload;
  check_edit "link with another external_id appends 1 entry" 1 db
    [
      References.link ~plant:p.id ~source:Source.Gbif ~external_id:"2"
        ~url:"https://www.gbif.org/species/1-updated" ~at:t2;
    ];
  check_edit "link back to the first external_id appends 1 entry" 1 db
    [
      References.link ~plant:p.id ~source:Source.Gbif ~external_id:"1"
        ~url:"https://www.gbif.org/species/1-updated" ~at:t2;
    ];
  check_edit "unlink of the live link appends 1 entry" 1 db
    [References.unlink ~plant:p.id ~source:Source.Gbif ~at:t3];
  Alcotest.(check Cli.yojson)
    "the unlink's entry"
    (plant_ref_payload ~id:gbif_id_str ~plant:p.id ~source:Source.Gbif
       ~external_id:"1" ~url:"https://www.gbif.org/species/1-updated"
       ~created_at:t1 ~updated_at:t3 ~deleted_at:(Some t3))
    (last db).payload;
  check_edit "unlink again appends nothing" 0 db
    [References.unlink ~plant:p.id ~source:Source.Gbif ~at:t3];
  check_edit "link on the deleted row (revive) appends 1 entry" 1 db
    [
      References.link ~plant:p.id ~source:Source.Gbif ~external_id:"1"
        ~url:"https://www.gbif.org/species/1-updated" ~at:t3;
    ];
  Alcotest.(check string)
    "the revive's row_id is the stored id" gbif_id_str (last db).row_id;
  Alcotest.(check Cli.yojson)
    "the revive's entry"
    (plant_ref_payload ~id:gbif_id_str ~plant:p.id ~source:Source.Gbif
       ~external_id:"1" ~url:"https://www.gbif.org/species/1-updated"
       ~created_at:t1 ~updated_at:t3 ~deleted_at:None)
    (last db).payload;
  check_edit "a second source" 1 db
    [
      References.link ~plant:p.id ~source:Source.Wikidata ~external_id:"Q1"
        ~url:"https://www.wikidata.org/wiki/Q1" ~at:t3;
    ];
  check_edit "a third source, linked" 1 db
    [
      References.link ~plant:p.id ~source:Source.Inat ~external_id:"53983"
        ~url:"https://www.inaturalist.org/taxa/53983" ~at:t3;
    ];
  check_edit "then unlinked" 1 db
    [References.unlink ~plant:p.id ~source:Source.Inat ~at:t3];
  match Cli.all db (References.plant_refs p.id) with
  | [(a : Reference.Plant_ref.t); (b : Reference.Plant_ref.t)] ->
      Alcotest.(check string)
        "first, by source label" "gbif"
        (Source.to_string a.source);
      Alcotest.(check string) "second" "wikidata" (Source.to_string b.source)
  | refs ->
      Alcotest.failf
        "expected 2 live plant refs (the unlinked inat excluded), got %d"
        (List.length refs)

(* ---------- input / plant_ref_input cover their table's columns ---------- *)

let input_covers_table () =
  let db = Cli.migrated_db () in
  let keys json =
    match json with
    | `Assoc kvs -> List.sort String.compare (List.map fst kvs)
    | other -> Alcotest.failf "input %s" (Yojson.Safe.to_string other)
  in
  let r : Reference.t =
    {
      id = reference_id 0x1;
      plant_id = plant_id 0x1;
      source = Source.Gbif;
      fetched_at = t1;
      payload = payload_a;
      status = Status.Complete;
      created_at = t1;
      updated_at = t1;
      deleted_at = None;
    }
  in
  let pr : Reference.Plant_ref.t =
    {
      id = plant_ref_id 0x1;
      plant_id = plant_id 0x1;
      source = Source.Gbif;
      external_id = "1";
      url = "https://www.gbif.org/species/1";
      created_at = t1;
      updated_at = t1;
      deleted_at = None;
    }
  in
  List.iter
    (fun (table, input) ->
      Alcotest.(check (list string))
        (table ^ ": the input's keys are the table's columns")
        (Cli.column_names db table)
        (keys input))
    [
      ("reference", Input.to_json (References.input r));
      ("plant_refs", Input.to_json (References.plant_ref_input pr));
    ]

(* ---------- run ---------- *)

let case name f = Alcotest.test_case name `Quick f

let () =
  Alcotest.run "store references"
    [
      ( "put",
        [
          case "put: a new row, read back structurally equal, one entry"
            put_new_row;
          case
            "put again: same id, created_at kept, updated_at and payload change"
            put_again_updates;
          case "put over a row stored with a different id (a pull) keeps it"
            put_over_a_pulled_row_keeps_its_id;
          case "put revives a soft-deleted row" put_revives_a_soft_deleted_row;
          case "put for an unknown plant fails on the foreign key"
            put_for_unknown_plant_fails;
        ] );
      ( "of_plant, get",
        [
          case
            "of_plant orders by source, excludes soft-deleted and other \
             plants; get on an absent row is 0 rows"
            of_plant_orders_filters_live_and_by_plant;
        ] );
      ( "remove",
        [
          case
            "remove on a live row: one change, deleted_at = updated_at = at, \
             id and payload kept"
            remove_live_row_soft_deletes;
          case "remove on a missing or already-deleted row is a no-op"
            remove_no_row_or_already_deleted_is_a_no_op;
          case "put after remove revives the row, same id"
            put_after_remove_revives;
          case "remove of one source leaves another source's row untouched"
            remove_another_source_untouched;
        ] );
      ( "link, unlink, plant_refs",
        [
          case
            "link revives, updates only on change; unlink soft-deletes; \
             plant_refs is ordered and live-only"
            link_unlink_and_plant_refs;
        ] );
      ( "Input",
        [
          case "input and plant_ref_input cover their table's columns"
            input_covers_table;
        ] );
    ]
