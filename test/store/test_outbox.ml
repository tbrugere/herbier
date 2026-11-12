(* Native checks of app/store/outbox.ml and of the outbox entries every
   per-table edit appends, through the sqlite3 CLI:
   Sqlite_cli.edit runs each edit as Db.edit does on the device (statement,
   read-back, appended entry), without the transaction. The transaction, its
   rollback, the serialisation of Db and the plugin's transaction flag are
   device checks (#dev/store, outbox group). *)

module Ids = Herbier_domain.Ids
module Plant = Herbier_domain.Plant
module Observation = Herbier_domain.Observation
module Photo = Herbier_domain.Photo
module Tag = Herbier_domain.Tag
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
let observation_id = id_of "observation id" Ids.Observation_id.of_string
let photo_id = id_of "photo id" Ids.Photo_id.of_string
let tag_id = id_of "tag id" Ids.Tag_id.of_string
let plant_tag_id = id_of "plant tag id" Ids.Plant_tag_id.of_string
let t0 = time "2026-10-28T12:00:00Z"
let t1 = time "2026-10-28T12:00:01.000001Z"
let t2 = time "2026-10-28T14:00:02.5+02:00"
let t3 = time "2026-10-28T12:00:03.999999Z"

let plant ?(aliases = []) ?scientific_name ?authorship ?gbif_key ?(notes = "")
    ?notes_updated_at ?cover_photo_id ?(created_at = t0) ?(updated_at = t0)
    ?deleted_at n display_name : Plant.t =
  {
    id = plant_id n;
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

let observation ?plant ?position ?place_label ?note ?(created_at = t0)
    ?(updated_at = t0) n at : Observation.t =
  {
    id = observation_id n;
    plant_id = Option.map plant_id plant;
    at;
    position;
    place_label;
    place_derived = None;
    note;
    created_at;
    updated_at;
    deleted_at = None;
  }

let photo ~observation n taken_at : Photo.t =
  {
    id = photo_id n;
    observation_id = observation_id observation;
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

let tag ?(created_at = t0) ?(updated_at = t0) n name : Tag.t =
  {id = tag_id n; name; created_at; updated_at; deleted_at = None}

let full_plant =
  plant 0x2 "Rose 'Albertine', \"grimpant\""
    ~aliases:["Églantier"; "dog rose, \"wild\""]
    ~scientific_name:"Rosa canina" ~authorship:"L." ~gbif_key:8395064
    ~notes:"Ligne 1;\nligne 2 -- pas un commentaire ?"
    ~notes_updated_at:(time "2026-10-28T14:00:05.123456+02:00")
    ~created_at:(time "2026-01-01T00:00:00Z")
    ~updated_at:t1

(* ---------- expected values, built without the code under test ---------- *)

let ts_json t = Col.to_json (Not_Null TimestampTz) t
let ts_opt_json t = Col.to_json (Nullable TimestampTz) t
let str s = `String s
let opt f = function None -> `Null | Some v -> f v

let plant_columns =
  [
    "id";
    "display_name";
    "aliases";
    "scientific_name";
    "authorship";
    "gbif_key";
    "notes";
    "notes_updated_at";
    "cover_photo_id";
    "created_at";
    "updated_at";
    "deleted_at";
  ]

(* A PostgREST upsert body for a plant, by hand: every column of
   Tables.Plants in declaration order, aliases a JSON array. *)
let plant_payload (p : Plant.t) : Yojson.Safe.t =
  `Assoc
    [
      ("id", str (Ids.Plant_id.to_string p.id));
      ("display_name", str p.display_name);
      ("aliases", `List (List.map str p.aliases));
      ("scientific_name", opt str p.scientific_name);
      ("authorship", opt str p.authorship);
      ("gbif_key", opt (fun n -> `Int n) p.gbif_key);
      ("notes", str p.notes);
      ("notes_updated_at", ts_opt_json p.notes_updated_at);
      ( "cover_photo_id",
        opt (fun x -> str (Ids.Photo_id.to_string x)) p.cover_photo_id );
      ("created_at", ts_json p.created_at);
      ("updated_at", ts_json p.updated_at);
      ("deleted_at", ts_opt_json p.deleted_at);
    ]

let plant_tag_payload ~id ~plant ~tag ~created_at ~updated_at ~deleted_at :
    Yojson.Safe.t =
  `Assoc
    [
      ("id", str id);
      ("plant_id", str (Ids.Plant_id.to_string plant));
      ("tag_id", str (Ids.Tag_id.to_string tag));
      ("created_at", ts_json created_at);
      ("updated_at", ts_json updated_at);
      ("deleted_at", ts_opt_json deleted_at);
    ]

(* The bodies below use the fixtures' literal values: they check each
   table's input against what PostgREST expects, not against itself. *)

(* An observation's body for [observation 0x31 t1 ~plant:0x1] with the
   position and labels of [with_position] below. *)
let observation_payload ~updated_at ~deleted_at : Yojson.Safe.t =
  `Assoc
    [
      ("id", str (uuid 0x31));
      ("plant_id", str (uuid 0x1));
      ("at", ts_json t1);
      ("lat", `Float 48.0625);
      ("lon", `Float 7.0625);
      ("accuracy_m", `Float 12.5);
      ("place_label", str "Lac Blanc, rive \"nord\"");
      ("place_derived", `Null);
      ("note", str "l'eau");
      ("created_at", ts_json t0);
      ("updated_at", ts_json updated_at);
      ("deleted_at", ts_opt_json deleted_at);
    ]

(* A photo's body for [photo 0xf1 ~observation:0x31 t1]. *)
let photo_payload ~updated_at ~deleted_at : Yojson.Safe.t =
  `Assoc
    [
      ("id", str (uuid 0xf1));
      ("observation_id", str (uuid 0x31));
      ("taken_at", ts_json t1);
      ("width", `Int 1024);
      ("height", `Int 768);
      ("sha256", str (String.make 64 'a'));
      ("preview_path", str "previews/241.webp");
      ("preview_bucket_key", `Null);
      ("original_target", str "drive");
      ("drive_file_id", `Null);
      ("upload_state", str "pending");
      ("created_at", ts_json t0);
      ("updated_at", ts_json updated_at);
      ("deleted_at", ts_opt_json deleted_at);
    ]

let tag_payload (t : Tag.t) : Yojson.Safe.t =
  `Assoc
    [
      ("id", str (Ids.Tag_id.to_string t.id));
      ("name", str t.name);
      ("created_at", ts_json t.created_at);
      ("updated_at", ts_json t.updated_at);
      ("deleted_at", ts_opt_json t.deleted_at);
    ]

(* ---------- raw outbox rows ---------- *)

type raw = {
  seq : int;
  table_name : string;
  row_id : string;
  op : string;
  payload : Yojson.Safe.t;
  created_at : string;
  attempts : int;
  last_error : string option;
}

let raw_of_row row =
  let payload_text = Cli.string_field "payload_json" row in
  let payload =
    match Yojson.Safe.from_string payload_text with
    | j -> j
    | exception Yojson.Json_error m ->
        Alcotest.failf "payload_json %S is not JSON: %s" payload_text m
  in
  {
    seq = Cli.int_field "seq" row;
    table_name = Cli.string_field "table_name" row;
    row_id = Cli.string_field "row_id" row;
    op = Cli.string_field "op" row;
    payload;
    created_at = Cli.string_field "created_at" row;
    attempts = Cli.int_field "attempts" row;
    last_error =
      (match Cli.field "last_error" row with
      | `Null -> None
      | `String s -> Some s
      | other -> Alcotest.failf "last_error is %s" (Yojson.Safe.to_string other));
  }

let outbox db = List.map raw_of_row (Cli.outbox db)

let last db =
  match List.rev (outbox db) with
  | r :: _ -> r
  | [] -> Alcotest.fail "the outbox is empty"

(* The entry at position [i] (0 first) of the outbox, in seq order. *)
let nth db i =
  match List.filteri (fun j _ -> j = i) (outbox db) with
  | [r] -> r
  | _ -> Alcotest.failf "the outbox has no entry %d" i

let check_count what expected db =
  Alcotest.(check int) what expected (Cli.outbox_count db)

let check_edit what expected db edits =
  Alcotest.(check int) what expected (Cli.edit_ok what db edits)

let payload_field name (r : raw) = Cli.field name r.payload

let check_entry what ~table ~row_id ~payload (r : raw) =
  Alcotest.(check string) (what ^ ": table_name") table r.table_name;
  Alcotest.(check string) (what ^ ": row_id") row_id r.row_id;
  Alcotest.(check string) (what ^ ": op is upsert") "upsert" r.op;
  Alcotest.(check Cli.yojson) (what ^ ": payload") payload r.payload;
  Alcotest.(check int) (what ^ ": attempts is 0") 0 r.attempts;
  Alcotest.(check (option string))
    (what ^ ": last_error is null")
    None r.last_error

(* "YYYY-MM-DDTHH:MM:SS.ffffffZ", Codec.timestamp's format. *)
let timestamp_shaped s =
  let digit c = c >= '0' && c <= '9' in
  String.length s = 27
  && List.for_all
       (fun i ->
         match i with
         | 4 | 7 -> s.[i] = '-'
         | 10 -> s.[i] = 'T'
         | 13 | 16 -> s.[i] = ':'
         | 19 -> s.[i] = '.'
         | 26 -> s.[i] = 'Z'
         | _ -> digit s.[i])
       (List.init 27 Fun.id)

let check_created_at what s =
  Alcotest.(check bool)
    (what ^ ": created_at is YYYY-MM-DDTHH:MM:SS.ffffffZ")
    true (timestamp_shaped s);
  Alcotest.(check string)
    (what ^ ": created_at is milliseconds padded with 000")
    "000" (String.sub s 23 3);
  match Ptime.of_rfc3339 s with
  | Ok (t, Some 0, _) ->
      Alcotest.(check bool)
        (what ^ ": created_at is after 2026-01-01")
        true
        (Ptime.is_later t ~than:(time "2026-01-01T00:00:00Z"))
  | Ok (_, (None | Some _), _) | Error _ ->
      Alcotest.failf "%s: created_at %S is not RFC 3339 UTC" what s

(* ---------- outbox grows with edits ---------- *)

let grows_with_edits () =
  let db = Cli.migrated_db () in
  let p = full_plant in
  check_count "a fresh database has an empty outbox" 0 db;
  check_edit "upserting a plant appends 1 entry" 1 db [Plants.upsert p];
  let first = last db in
  check_entry "the plant's entry" ~table:"plants"
    ~row_id:(Ids.Plant_id.to_string p.id)
    ~payload:(Input.to_json (Plants.input p))
    first;
  check_created_at "the plant's entry" first.created_at;
  let renamed = {p with display_name = "Églantier"; updated_at = t2} in
  check_edit "upserting the renamed plant appends 1 entry" 1 db
    [Plants.upsert renamed];
  check_count "two upserts give two entries" 2 db;
  let second = last db in
  Alcotest.(check bool)
    "the second entry's seq is greater" true (second.seq > first.seq);
  Alcotest.(check Cli.yojson)
    "the second payload carries the new name" (str "Églantier")
    (payload_field "display_name" second);
  Alcotest.(check Cli.yojson)
    "the first payload still carries the old name" (str p.display_name)
    (payload_field "display_name" (nth db 0));
  check_edit "soft_delete of the live plant appends 1 entry" 1 db
    [Plants.soft_delete p.id ~at:t3];
  check_count "three entries" 3 db;
  let third = last db in
  Alcotest.(check Cli.yojson)
    "the soft delete's payload has deleted_at = at" (ts_opt_json (Some t3))
    (payload_field "deleted_at" third);
  Alcotest.(check Cli.yojson)
    "the soft delete's payload is the whole deleted row"
    (Input.to_json
       (Plants.input {renamed with updated_at = t3; deleted_at = Some t3}))
    third.payload;
  check_edit "soft_delete again appends nothing" 0 db
    [Plants.soft_delete p.id ~at:t3];
  check_edit "soft_delete of an absent plant appends nothing" 0 db
    [Plants.soft_delete (plant_id 0x99) ~at:t3];
  check_count "still three entries" 3 db

let edit_empty () =
  let db = Cli.migrated_db () in
  check_edit "no edit appends nothing" 0 db [];
  check_count "the outbox stays empty" 0 db

let payload_shape () =
  let db = Cli.migrated_db () in
  let p =
    plant 0x1 "Pissenlit" ~aliases:["a"; "b"] ~created_at:t1 ~updated_at:t1
  in
  check_edit "upsert appends 1 entry" 1 db [Plants.upsert p];
  let r = last db in
  Alcotest.(check Cli.yojson)
    "aliases is a JSON array, not a string"
    (`List [str "a"; str "b"])
    (payload_field "aliases" r);
  Alcotest.(check (list string))
    "every column of Tables.Plants, in declaration order" plant_columns
    (match r.payload with
    | `Assoc kvs -> List.map fst kvs
    | other -> Alcotest.failf "payload %s" (Yojson.Safe.to_string other));
  List.iter
    (fun column ->
      Alcotest.(check Cli.yojson)
        (column ^ " absent from the record is null")
        `Null (payload_field column r))
    [
      "scientific_name";
      "authorship";
      "gbif_key";
      "notes_updated_at";
      "cover_photo_id";
      "deleted_at";
    ];
  Alcotest.(check Cli.yojson)
    "the payload is the PostgREST body of the stored row" (plant_payload p)
    r.payload;
  check_edit "upserting the full plant appends 1 entry" 1 db
    [Plants.upsert full_plant];
  Alcotest.(check Cli.yojson)
    "the full plant's payload, quotes, commas and newlines kept"
    (plant_payload full_plant) (last db).payload

(* ---------- per-table edits ---------- *)

let observations_and_photos () =
  let db = Cli.migrated_db () in
  check_edit "plant" 1 db [Plants.upsert (plant 0x1 "Pissenlit")];
  let with_position =
    observation 0x31 t1 ~plant:0x1
      ~position:{lat = 48.0625; lon = 7.0625; accuracy_m = Some 12.5}
      ~place_label:"Lac Blanc, rive \"nord\"" ~note:"l'eau"
  in
  let without_accuracy =
    observation 0x32 t2 ~position:{lat = -45.5; lon = 179.5; accuracy_m = None}
  in
  let without_position = observation 0x33 t3 in
  List.iter
    (fun (what, (o : Observation.t)) ->
      check_edit
        (what ^ ": upsert appends 1 entry")
        1 db
        [Observations.upsert o];
      check_entry what ~table:"observations"
        ~row_id:(Ids.Observation_id.to_string o.id)
        ~payload:(Input.to_json (Observations.input o))
        (last db))
    [
      ("an observation with a position", with_position);
      ("an observation without accuracy", without_accuracy);
      ("an observation without position", without_position);
    ];
  Alcotest.(check Cli.yojson)
    "the observation with a position: its PostgREST body"
    (observation_payload ~updated_at:t0 ~deleted_at:None)
    (nth db 1).payload;
  List.iter
    (fun (column, expected) ->
      Alcotest.(check Cli.yojson)
        ("accuracy None: " ^ column)
        expected
        (payload_field column (nth db 2)))
    [("lat", `Float (-45.5)); ("lon", `Float 179.5); ("accuracy_m", `Null)];
  let r = last db in
  List.iter
    (fun column ->
      Alcotest.(check Cli.yojson)
        ("position None: " ^ column ^ " is null")
        `Null (payload_field column r))
    ["lat"; "lon"; "accuracy_m"];
  check_edit "observation soft_delete appends 1 entry" 1 db
    [Observations.soft_delete without_position.id ~at:t3];
  Alcotest.(check Cli.yojson)
    "its payload has deleted_at = at" (ts_opt_json (Some t3))
    (payload_field "deleted_at" (last db));
  check_edit "observation soft_delete again appends nothing" 0 db
    [Observations.soft_delete without_position.id ~at:t3];
  let ph = photo 0xf1 ~observation:0x31 t1 in
  check_edit "photo upsert appends 1 entry" 1 db [Photos.upsert ph];
  check_entry "the photo's entry" ~table:"photos"
    ~row_id:(Ids.Photo_id.to_string ph.id)
    ~payload:(photo_payload ~updated_at:t0 ~deleted_at:None)
    (last db);
  check_edit "photo soft_delete appends 1 entry" 1 db
    [Photos.soft_delete ph.id ~at:t2];
  check_entry "the deleted photo's entry" ~table:"photos"
    ~row_id:(Ids.Photo_id.to_string ph.id)
    ~payload:(photo_payload ~updated_at:t2 ~deleted_at:(Some t2))
    (last db);
  check_edit "photo soft_delete again appends nothing" 0 db
    [Photos.soft_delete ph.id ~at:t3];
  check_edit "soft deletes of an absent observation and photo append nothing" 0
    db
    [
      Observations.soft_delete (observation_id 0x99) ~at:t3;
      Photos.soft_delete (photo_id 0x99) ~at:t3;
    ];
  check_count "one entry per changing write" 7 db

let observations_set_place_derived () =
  let db = Cli.migrated_db () in
  let lat = 48.0625 and lon = 7.0625 in
  let o =
    observation 0x31 t1 ~position:{lat; lon; accuracy_m = Some 5.} ~note:"l'eau"
  in
  check_edit "observation upsert" 1 db [Observations.upsert o];
  check_edit "set_place_derived of a live, unnamed observation appends 1 entry"
    1 db
    [
      Observations.set_place_derived (observation_id 0x31) ~lat ~lon
        "Près du Lac Blanc" ~at:t2;
    ];
  check_entry "the filled observation's entry" ~table:"observations"
    ~row_id:(uuid 0x31)
    ~payload:
      (Input.to_json
         (Observations.input
            {o with place_derived = Some "Près du Lac Blanc"; updated_at = t2}))
    (last db);
  check_edit "set_place_derived again (already named) appends nothing" 0 db
    [
      Observations.set_place_derived (observation_id 0x31) ~lat ~lon
        "Près d'ailleurs" ~at:t3;
    ];
  check_count "one entry, from the fill only" 2 db

let tags_and_links () =
  let db = Cli.migrated_db () in
  let p = plant 0xa "Thym" in
  let t = tag 0xc1 "Plantes d'ombre, \"humides\"" ~created_at:t1 in
  check_edit "plant" 1 db [Plants.upsert p];
  check_edit "Tags.upsert appends 1 entry" 1 db [Tags.upsert t];
  check_entry "the tag's entry" ~table:"tags"
    ~row_id:(Ids.Tag_id.to_string t.id)
    ~payload:(tag_payload t) (last db);
  let link_id =
    Ids.Plant_tag_id.to_string (Ids.Plant_tag_id.of_key ~plant:p.id ~tag:t.id)
  in
  let link = plant_tag_payload ~id:link_id ~plant:p.id ~tag:t.id in
  check_edit "tag on a missing link appends 1 entry" 1 db
    [Tags.tag ~plant:p.id ~tag:t.id ~at:t1];
  check_entry "the new link's entry" ~table:"plant_tags" ~row_id:link_id
    ~payload:(link ~created_at:t1 ~updated_at:t1 ~deleted_at:None)
    (last db);
  check_edit "tag on a live link appends nothing" 0 db
    [Tags.tag ~plant:p.id ~tag:t.id ~at:t2];
  check_edit "untag of the live link appends 1 entry" 1 db
    [Tags.untag ~plant:p.id ~tag:t.id ~at:t2];
  check_entry "the untag's entry" ~table:"plant_tags" ~row_id:link_id
    ~payload:(link ~created_at:t1 ~updated_at:t2 ~deleted_at:(Some t2))
    (last db);
  check_edit "untag again appends nothing" 0 db
    [Tags.untag ~plant:p.id ~tag:t.id ~at:t3];
  check_edit "tag on the deleted link (revive) appends 1 entry" 1 db
    [Tags.tag ~plant:p.id ~tag:t.id ~at:t3];
  check_entry "the revive's entry" ~table:"plant_tags" ~row_id:link_id
    ~payload:(link ~created_at:t1 ~updated_at:t3 ~deleted_at:None)
    (last db);
  check_edit "Tags.soft_delete appends 1 entry" 1 db
    [Tags.soft_delete t.id ~at:t3];
  check_entry "the deleted tag's entry" ~table:"tags"
    ~row_id:(Ids.Tag_id.to_string t.id)
    ~payload:(tag_payload {t with updated_at = t3; deleted_at = Some t3})
    (last db);
  check_edit "Tags.soft_delete again appends nothing" 0 db
    [Tags.soft_delete t.id ~at:t3];
  check_edit "soft_delete of an absent tag appends nothing" 0 db
    [Tags.soft_delete (tag_id 0x99) ~at:t3];
  check_count "one entry per changing write" 6 db

let link_keeps_stored_id () =
  let db = Cli.migrated_db () in
  let p = plant 0xa "Thym" in
  let t = tag 0xc1 "Jardin" in
  let stored = plant_tag_id 0xd1 in
  check_edit "plant and tag" 2 db [Plants.upsert p; Tags.upsert t];
  let (_ : int) =
    Cli.write_ok "a pulled link" db
      (Tags.upsert_plant_tag
         {
           id = stored;
           plant_id = p.id;
           tag_id = t.id;
           created_at = t0;
           updated_at = t0;
           deleted_at = None;
         })
  in
  check_count "upsert_plant_tag appends no entry" 2 db;
  check_edit "untag of the pulled link appends 1 entry" 1 db
    [Tags.untag ~plant:p.id ~tag:t.id ~at:t2];
  let r = last db in
  Alcotest.(check string)
    "the entry's row_id is the stored id, not of_key" (uuid 0xd1) r.row_id;
  Alcotest.(check Cli.yojson)
    "the payload is the stored link, deleted at t2"
    (plant_tag_payload ~id:(uuid 0xd1) ~plant:p.id ~tag:t.id ~created_at:t0
       ~updated_at:t2 ~deleted_at:(Some t2))
    r.payload;
  check_edit "tag on it (revive) appends 1 entry" 1 db
    [Tags.tag ~plant:p.id ~tag:t.id ~at:t3];
  Alcotest.(check string)
    "the revive's row_id is the stored id" (uuid 0xd1) (last db).row_id

let failing_edit_appends_nothing () =
  let db = Cli.migrated_db () in
  check_edit "plant" 1 db [Plants.upsert (plant 0x1 "Pissenlit")];
  (match
     Cli.edit db [Observations.upsert (observation 0x31 t1 ~plant:0x99)]
   with
  | Ok n ->
      Alcotest.failf
        "an observation of an unknown plant should fail, appended %d" n
  | Error stderr ->
      Alcotest.(check bool)
        "it fails on the foreign key" true
        (Cli.contains ~sub:"FOREIGN KEY constraint failed" stderr));
  check_count "the outbox is unchanged" 1 db;
  Alcotest.(check int)
    "the observation is absent" 0
    (Cli.count db "select count(*) as n from observations;\n")

(* Cli.edit has no transaction, so the edit before the failing one stays
   written here; on the device Db.edit rolls it back too (#dev/store). *)
let stops_at_first_failure () =
  let db = Cli.migrated_db () in
  let a = plant 0x1 "A" and b = plant 0x2 "B" in
  (match
     Cli.edit db
       [
         Plants.upsert a;
         Observations.upsert (observation 0x31 t1 ~plant:0x99);
         Plants.upsert b;
       ]
   with
  | Ok n -> Alcotest.failf "the middle edit should fail, appended %d" n
  | Error (_ : string) -> ());
  Alcotest.(check (list string))
    "only the first edit's entry, nothing after the failure"
    [Ids.Plant_id.to_string a.id]
    (List.map (fun (r : raw) -> r.row_id) (outbox db));
  Alcotest.(check int)
    "plant b, after the failing edit, is absent" 0
    (Cli.count db
       (Printf.sprintf "select count(*) as n from plants where id = '%s';\n"
          (Ids.Plant_id.to_string b.id)))

let several_edits_in_order () =
  let db = Cli.migrated_db () in
  let p = plant 0x1 "Pissenlit" in
  let t = tag 0xc1 "Jardin" in
  check_edit "three edits append three entries" 3 db
    [Tags.upsert t; Plants.upsert p; Tags.tag ~plant:p.id ~tag:t.id ~at:t1];
  let rs = outbox db in
  Alcotest.(check (list string))
    "entries in the order of the edits"
    ["tags"; "plants"; "plant_tags"]
    (List.map (fun (r : raw) -> r.table_name) rs);
  Alcotest.(check (list string))
    "row ids in the order of the edits"
    [
      Ids.Tag_id.to_string t.id;
      Ids.Plant_id.to_string p.id;
      Ids.Plant_tag_id.to_string (Ids.Plant_tag_id.of_key ~plant:p.id ~tag:t.id);
    ]
    (List.map (fun (r : raw) -> r.row_id) rs);
  let seqs = List.map (fun (r : raw) -> r.seq) rs in
  Alcotest.(check (list int))
    "seq ascending"
    (List.sort_uniq Int.compare seqs)
    seqs

let dev_seed_appends_nothing () =
  let db = Cli.migrated_db () in
  Cli.write_all_ok "seed" db Dev_seed.statements;
  Alcotest.(check int)
    "the seed plants are present"
    (List.length Dev_seed.plants)
    (Cli.count db "select count(*) as n from plants;\n");
  check_count "the outbox stays empty" 0 db

(* ---------- next, park, delete ---------- *)

let entry_json (e : Outbox.entry) : Yojson.Safe.t =
  `Assoc
    [
      ("seq", `Int (Outbox.seq_to_int e.seq));
      ("table_name", str e.table_name);
      ("row_id", str e.row_id);
      ("op", str (match e.op with Outbox.Upsert -> "upsert"));
      ("payload", e.payload);
      ("created_at", str (Codec.timestamp e.created_at));
      ("attempts", `Int e.attempts);
      ("last_error", opt str e.last_error);
    ]

let raw_json (r : raw) : Yojson.Safe.t =
  `Assoc
    [
      ("seq", `Int r.seq);
      ("table_name", str r.table_name);
      ("row_id", str r.row_id);
      ("op", str r.op);
      ("payload", r.payload);
      ("created_at", str r.created_at);
      ("attempts", `Int r.attempts);
      ("last_error", opt str r.last_error);
    ]

let three_entries () =
  let db = Cli.migrated_db () in
  check_edit "three plants" 3 db
    [
      Plants.upsert (plant 0x3 "C");
      Plants.upsert (plant 0x1 "A");
      Plants.upsert (plant 0x2 "B");
    ];
  db

let next db ~limit = Cli.all db (Outbox.next ~limit)
let seqs es = List.map (fun (e : Outbox.entry) -> Outbox.seq_to_int e.seq) es
let raw_seqs db = List.map (fun (r : raw) -> r.seq) (outbox db)

let next_order () =
  let db = three_entries () in
  let es = next db ~limit:10 in
  Alcotest.(check (list Cli.yojson))
    "next gives every entry as stored, in seq order"
    (List.map raw_json (outbox db))
    (List.map entry_json es);
  List.iter
    (fun (e : Outbox.entry) ->
      Alcotest.(check bool)
        "the payload is parsed (an object, not a string)" true
        (match e.payload with `Assoc _ -> true | _ -> false))
    es;
  Alcotest.(check (list string))
    "row ids in append order"
    [uuid 0x3; uuid 0x1; uuid 0x2]
    (List.map (fun (e : Outbox.entry) -> e.row_id) es);
  Alcotest.(check (list int))
    "~limit:2 of 3 gives the first two"
    (List.filteri (fun i _ -> i < 2) (raw_seqs db))
    (seqs (next db ~limit:2));
  Alcotest.(check (list int))
    "~limit:1 gives the first" [(nth db 0).seq]
    (seqs (next db ~limit:1));
  Alcotest.(check (list int)) "~limit:0 gives none" [] (seqs (next db ~limit:0));
  Alcotest.(check (list int))
    "~limit:(-1) gives none" []
    (seqs (next db ~limit:(-1)))

let next_empty () =
  let db = Cli.migrated_db () in
  Alcotest.(check (list int))
    "next on an empty outbox is []" []
    (seqs (next db ~limit:10))

let park () =
  let db = three_entries () in
  let (first : Outbox.entry), rest =
    match next db ~limit:10 with
    | e :: rest -> (e, rest)
    | [] -> Alcotest.fail "no entry"
  in
  Alcotest.(check int)
    "park of an entry changes 1 row" 1
    (Cli.write_ok "park" db (Outbox.park first.seq ~error:"409 conflict"));
  Alcotest.(check (list int))
    "the parked entry leaves next" (seqs rest)
    (seqs (next db ~limit:10));
  Alcotest.(check (list int))
    "~limit counts unparked entries only"
    (seqs (List.filteri (fun i _ -> i = 0) rest))
    (seqs (next db ~limit:1));
  let parked () =
    match
      List.find_opt
        (fun (r : raw) -> r.seq = Outbox.seq_to_int first.seq)
        (outbox db)
    with
    | Some r -> r
    | None -> Alcotest.fail "the parked entry's row is gone"
  in
  Alcotest.(check (option string))
    "its row has last_error" (Some "409 conflict") (parked ()).last_error;
  Alcotest.(check int) "its attempts is 1" 1 (parked ()).attempts;
  Alcotest.(check Cli.yojson)
    "its payload is kept" first.payload (parked ()).payload;
  let message = "422: \"plants_pkey\", l'id -- ?" in
  Alcotest.(check int)
    "park again changes 1 row" 1
    (Cli.write_ok "park again" db (Outbox.park first.seq ~error:message));
  Alcotest.(check int) "attempts is 2" 2 (parked ()).attempts;
  Alcotest.(check (option string))
    "last_error is the new message, quotes kept" (Some message)
    (parked ()).last_error;
  let (second : Outbox.entry) =
    match rest with
    | e :: _ -> e
    | [] -> Alcotest.fail "next gave one entry, expected 3"
  in
  let (_ : int) = Cli.write_ok "delete" db (Outbox.delete second.seq) in
  Alcotest.(check int)
    "park of a deleted entry changes 0 rows" 0
    (Cli.write_ok "park deleted" db (Outbox.park second.seq ~error:"x"))

let delete () =
  let db = three_entries () in
  let before = raw_seqs db in
  let (second : Outbox.entry) =
    match next db ~limit:10 with
    | [_; e; _] -> e
    | es -> Alcotest.failf "%d entries, expected 3" (List.length es)
  in
  Alcotest.(check int)
    "delete of an entry changes 1 row" 1
    (Cli.write_ok "delete" db (Outbox.delete second.seq));
  Alcotest.(check (list int))
    "the others stay, in order"
    (List.filter (fun s -> s <> Outbox.seq_to_int second.seq) before)
    (raw_seqs db);
  Alcotest.(check (list int))
    "next no longer gives it"
    (List.filter (fun s -> s <> Outbox.seq_to_int second.seq) before)
    (seqs (next db ~limit:10));
  Alcotest.(check int)
    "delete again changes 0 rows" 0
    (Cli.write_ok "delete again" db (Outbox.delete second.seq))

(* payload_json is in next's ~json, so text that is not JSON is
   Invalid_json_column. *)
let next_decode_errors () =
  let insert db ~op ~payload ~last_error =
    Cli.exec_ok "raw outbox row" db
      (Printf.sprintf
         "insert into outbox (table_name, row_id, op, payload_json, \
          created_at, last_error) values ('plants', '%s', '%s', '%s', \
          '2026-10-28T12:00:00.000000Z', %s);\n"
         (uuid 1) op payload last_error)
  in
  let db = Cli.migrated_db () in
  insert db ~op:"delete" ~payload:"{}" ~last_error:"null";
  Alcotest.(check (list (result Cli.yojson Cli.codec_error)))
    "an entry whose op is not upsert does not decode" [Error (Row `WrongType)]
    (List.map (Result.map entry_json)
       (Cli.all_results db (Outbox.next ~limit:10)));
  let db = Cli.migrated_db () in
  insert db ~op:"upsert" ~payload:"not json" ~last_error:"null";
  Alcotest.(check (list (result Cli.yojson Cli.codec_error)))
    "an entry whose payload is not JSON does not decode"
    [Error (Invalid_json_column "payload_json")]
    (List.map (Result.map entry_json)
       (Cli.all_results db (Outbox.next ~limit:10)));
  let db = Cli.migrated_db () in
  insert db ~op:"upsert" ~payload:"{}" ~last_error:"'500'";
  Alcotest.(check (list int))
    "a row with last_error set is not in next" []
    (seqs (next db ~limit:10))

(* ---------- append ---------- *)

let append_errors () =
  let e = Plants.upsert (plant 0x1 "Pissenlit") in
  List.iter
    (fun (what, text) ->
      match Outbox.append e text with
      | Error (Invalid_row _) -> ()
      | Error err ->
          Alcotest.failf "%s: expected Invalid_row, got %s" what
            (Cli.string_of_codec_error err)
      | Ok _ -> Alcotest.failf "%s: expected Invalid_row, got Ok" what)
    [
      ("a JSON array", "[1]");
      ("text that is not JSON", "not json");
      ("empty text", "");
    ];
  match Outbox.append e (Printf.sprintf {|{"id": "%s"}|} (uuid 1)) with
  | Error err ->
      Alcotest.check Cli.codec_error "an object missing a column is Row Missing"
        (Row `Missing) err
  | Ok _ -> Alcotest.fail "an object missing a column should not append"

let reread_finds_deleted_row () =
  let db = Cli.migrated_db () in
  let p = plant 0x1 "Pissenlit" ~deleted_at:t1 in
  let (_ : int) =
    Cli.write_ok "a deleted plant" db (Outbox.without_entry (Plants.upsert p))
  in
  Alcotest.(check int)
    "the read-back of a soft-deleted row gives it" 1
    (List.length (Cli.rows db (Cli.inline (Outbox.reread (Plants.upsert p)))))

(* ---------- Stmt.upsert from an Input ---------- *)

(* The names in the first parenthesised list of [sql]. *)
let column_list sql =
  match (String.index_opt sql '(', String.index_opt sql ')') with
  | Some i, Some j when i < j ->
      List.map String.trim
        (String.split_on_char ',' (String.sub sql (i + 1) (j - i - 1)))
  | _ -> Alcotest.failf "no column list in %S" sql

let after ~sub sql =
  match Cli.find_from ~sub sql 0 with
  | Some i ->
      let k = i + String.length sub in
      String.sub sql k (String.length sql - k)
  | None -> Alcotest.failf "%S has no %S" sql sub

let stmt_upsert () =
  let t = tag 0xc1 "Jardin" ~created_at:t1 ~updated_at:t2 in
  let s = Stmt.upsert ~table:Tables.Tags.table (Tags.input t) in
  let sql = String.lowercase_ascii s.sql in
  Alcotest.(check (list string))
    "the columns in the order of the input's fields"
    ["id"; "name"; "created_at"; "updated_at"; "deleted_at"]
    (column_list sql);
  Alcotest.(check bool)
    "it inserts into tags" true
    (Cli.contains ~sub:"insert into tags" sql);
  let update = after ~sub:"do update set" sql in
  List.iter
    (fun c ->
      Alcotest.(check bool)
        (c ^ " is in the update clause")
        true
        (Cli.contains ~sub:("excluded." ^ c) update))
    ["name"; "created_at"; "updated_at"; "deleted_at"];
  Alcotest.(check bool)
    "id is not in the update clause" false
    (Cli.contains ~sub:"excluded.id" update);
  Alcotest.(check (list Cli.param))
    "one parameter per column, in order"
    [
      Text (uuid 0xc1);
      Text "Jardin";
      Text (Codec.timestamp t1);
      Text (Codec.timestamp t2);
      Null;
    ]
    s.params

let stmt_upsert_only_id () =
  let only_id : (Tables.Tags.t, [`Full]) Input.t =
    {
      Input.fields =
        [Input.Mandatory (Tables.Tags.id, Input.Value (tag_id 0xc1))];
    }
  in
  let s = Stmt.upsert ~table:Tables.Tags.table only_id in
  Alcotest.(check bool)
    "an input with only id gives do nothing" true
    (Cli.contains ~sub:"do nothing" (String.lowercase_ascii s.sql));
  Alcotest.(check (list Cli.param))
    "its one parameter is the id"
    [Text (uuid 0xc1)]
    s.params

(* ---------- every column is in the payload ---------- *)

(* The keys of each table's input are the columns of the migrated table, so
   a column added to the schema but not to [input] (never written, never
   pushed) fails here. *)
let input_covers_table () =
  let db = Cli.migrated_db () in
  let keys json =
    match json with
    | `Assoc kvs -> List.sort String.compare (List.map fst kvs)
    | other -> Alcotest.failf "input %s" (Yojson.Safe.to_string other)
  in
  List.iter
    (fun (table, input) ->
      Alcotest.(check (list string))
        (table ^ ": the input's keys are the table's columns")
        (Cli.column_names db table)
        (keys input))
    [
      ("plants", Input.to_json (Plants.input full_plant));
      ( "observations",
        Input.to_json (Observations.input (observation 0x31 t1 ~plant:0x1)) );
      ("photos", Input.to_json (Photos.input (photo 0xf1 ~observation:0x31 t1)));
      ("tags", Input.to_json (Tags.input (tag 0xc1 "Jardin")));
      ( "plant_tags",
        Input.to_json
          (Tags.plant_tag_input
             {
               id = plant_tag_id 0xd1;
               plant_id = plant_id 0x1;
               tag_id = tag_id 0xc1;
               created_at = t0;
               updated_at = t0;
               deleted_at = None;
             }) );
    ]

(* ---------- cascades ---------- *)

let live db table where =
  Cli.count db
    (Printf.sprintf
       "select count(*) as n from %s where %s and deleted_at is null;\n" table
       where)

let is_ s = Printf.sprintf "'%s'" s
let pid n = is_ (Ids.Plant_id.to_string (plant_id n))
let oid n = is_ (Ids.Observation_id.to_string (observation_id n))

let cascades () =
  let db = Cli.migrated_db () in
  let thym = plant 0xa "Thym" and sauge = plant 0xb "Sauge" in
  let forest = tag 0xc1 "Forêt" and toxic = tag 0xc2 "Toxique" in
  let o1 = observation ~plant:0xa 0x31 t1
  and o2 = observation ~plant:0xa 0x32 t2
  and o3 = observation ~plant:0xb 0x33 t1 in
  let ph1 = photo 0xf1 ~observation:0x31 t1
  and ph2 = photo 0xf2 ~observation:0x32 t2
  and ph3 = photo 0xf3 ~observation:0x33 t1 in
  let (_ : int) =
    Cli.edit_ok "fixtures" db
      [
        Plants.upsert thym;
        Plants.upsert sauge;
        Tags.upsert forest;
        Tags.upsert toxic;
        Observations.upsert o1;
        Observations.upsert o2;
        Observations.upsert o3;
        Photos.upsert ph1;
        Photos.upsert ph2;
        Photos.upsert ph3;
        Tags.tag ~plant:thym.id ~tag:forest.id ~at:t1;
        Tags.tag ~plant:thym.id ~tag:toxic.id ~at:t1;
        Tags.tag ~plant:sauge.id ~tag:forest.id ~at:t1;
      ]
  in
  let thym_cascade =
    Cascade.plant ~at:t3 ~photos:[ph1.id; ph2.id] ~observations:[o1.id; o2.id]
      ~tags:[forest.id; toxic.id] thym.id
  in
  check_edit "the plant cascade appends one entry per row" 7 db thym_cascade;
  Alcotest.(check int)
    "the plant is deleted" 0
    (live db "plants" ("id = " ^ pid 0xa));
  Alcotest.(check int)
    "its observations are deleted" 0
    (live db "observations" ("plant_id = " ^ pid 0xa));
  Alcotest.(check int)
    "their photos are deleted" 0
    (live db "photos"
       (Printf.sprintf "observation_id in (%s, %s)" (oid 0x31) (oid 0x32)));
  Alcotest.(check int)
    "its tag links are deleted" 0
    (live db "plant_tags" ("plant_id = " ^ pid 0xa));
  Alcotest.(check int) "the tags stay" 2 (live db "tags" "1 = 1");
  Alcotest.(check int)
    "the other plant's observation stays" 1
    (live db "observations" ("plant_id = " ^ pid 0xb));
  Alcotest.(check int)
    "the other plant's photo stays" 1
    (live db "photos" ("observation_id = " ^ oid 0x33));
  Alcotest.(check int)
    "the other plant's link stays" 1
    (live db "plant_tags" ("plant_id = " ^ pid 0xb));
  check_edit "the plant cascade again appends nothing" 0 db thym_cascade;
  check_edit "the observation cascade appends one entry per row" 2 db
    (Cascade.observation ~at:t3 ~photos:[ph3.id] o3.id);
  Alcotest.(check int)
    "the observation is deleted" 0
    (live db "observations" ("id = " ^ oid 0x33));
  Alcotest.(check int)
    "its photo is deleted" 0
    (live db "photos" ("observation_id = " ^ oid 0x33));
  Alcotest.(check int)
    "its plant stays" 1
    (live db "plants" ("id = " ^ pid 0xb))

(* ---------- run ---------- *)

let () =
  let case name f = Alcotest.test_case name `Quick f in
  Alcotest.run "store outbox"
    [
      ( "Outbox grows with edits",
        [
          case "upserts and a soft delete append one entry each, in seq order"
            grows_with_edits;
          case "no edit appends nothing" edit_empty;
          case "the payload is the PostgREST body of every plant column"
            payload_shape;
        ] );
      ( "Per-table edits",
        [
          case "observations and photos append on upsert and soft_delete"
            observations_and_photos;
          case
            "set_place_derived appends 1 entry carrying the whole row when it \
             fills the name, none when already named"
            observations_set_place_derived;
          case "tag, untag and revive append; no-op links append nothing"
            tags_and_links;
          case "a link's entry carries the stored id, not of_key"
            link_keeps_stored_id;
          case "a failing edit appends nothing" failing_edit_appends_nothing;
          case "edits stop at the first failing one" stops_at_first_failure;
          case "several edits append in the order given" several_edits_in_order;
          case "Dev_seed.statements append nothing" dev_seed_appends_nothing;
          case "Cascade deletes the dependents of a plant, an observation"
            cascades;
        ] );
      ( "Outbox.next park delete",
        [
          case "next gives entries in seq order, payload parsed, limited"
            next_order;
          case "next on an empty outbox is empty" next_empty;
          case "park sets last_error and attempts and leaves next" park;
          case "delete removes exactly one entry" delete;
          case "next rejects an unknown op or a non-JSON payload, skips parked"
            next_decode_errors;
        ] );
      ( "Outbox.append and reread",
        [
          case "append rejects a non-object and a row missing a column"
            append_errors;
          case "reread finds a soft-deleted row" reread_finds_deleted_row;
        ] );
      ( "Input",
        [case "each input covers its table's columns" input_covers_table] );
      ( "Stmt.upsert",
        [
          case "columns follow the input, id stays out of the update" stmt_upsert;
          case "an input with only id is do nothing" stmt_upsert_only_id;
        ] );
    ]
