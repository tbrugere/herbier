(* Native checks of the pure store modules (Stmt, Plants,
   Observations, Tags, Photos, Settings, Search, Dev_seed): their statements
   run through the sqlite3 CLI on a database migrated with every
   Schema.batch, parameters inlined by position, rows decoded with
   Stmt.decode as Db.all does on the device. The Capacitor plugin itself is
   checked on the device (#dev/store, #dev/seed). *)

module Row = Postgrest.Row
module Ids = Herbier_domain.Ids
module Plant = Herbier_domain.Plant
module Observation = Herbier_domain.Observation
module Photo = Herbier_domain.Photo
module Tag = Herbier_domain.Tag
module P = Tables.Plants
module Cli = Sqlite_cli

(* These checks are about the bare statements and their changes() counts, so
   each write goes through [Outbox.without_entry] (no entry); test_outbox
   checks the entries. *)
module Plants = struct
  include Plants

  let upsert p = Outbox.without_entry (upsert p)
  let soft_delete id ~at = Outbox.without_entry (soft_delete id ~at)
end

module Observations = struct
  include Observations

  let upsert o = Outbox.without_entry (upsert o)
  let soft_delete id ~at = Outbox.without_entry (soft_delete id ~at)
end

module Photos = struct
  include Photos

  let upsert p = Outbox.without_entry (upsert p)
  let soft_delete id ~at = Outbox.without_entry (soft_delete id ~at)
end

module Tags = struct
  include Tags

  let upsert t = Outbox.without_entry (upsert t)
  let soft_delete id ~at = Outbox.without_entry (soft_delete id ~at)
  let tag ~plant ~tag:t ~at = Outbox.without_entry (tag ~plant ~tag:t ~at)
  let untag ~plant ~tag ~at = Outbox.without_entry (untag ~plant ~tag ~at)
end

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

let observation ?plant ?position ?place_label ?place_derived ?note
    ?(created_at = t0) ?(updated_at = t0) ?deleted_at n at : Observation.t =
  {
    id = observation_id n;
    plant_id = Option.map plant_id plant;
    at;
    position;
    place_label;
    place_derived;
    note;
    created_at;
    updated_at;
    deleted_at;
  }

let photo ?preview_bucket_key ?(original_target = Photo.Original_target.Drive)
    ?drive_file_id ?(upload_state = Photo.Upload_state.Pending)
    ?(created_at = t0) ?(updated_at = t0) ?deleted_at ~observation n taken_at :
    Photo.t =
  {
    id = photo_id n;
    observation_id = observation_id observation;
    taken_at;
    width = 1024;
    height = 768;
    sha256 = String.make 64 'a';
    preview_path = Printf.sprintf "previews/%d.webp" n;
    preview_bucket_key;
    original_target;
    drive_file_id;
    upload_state;
    created_at;
    updated_at;
    deleted_at;
  }

let tag ?(created_at = t0) ?(updated_at = t0) ?deleted_at n name : Tag.t =
  {id = tag_id n; name; created_at; updated_at; deleted_at}

(* ---------- testables ---------- *)

let ts t = `String (Ptime.to_rfc3339 ~frac_s:12 ~tz_offset_s:0 t)
let opt f = function None -> `Null | Some v -> f v
let str s = `String s

let plant_json (p : Plant.t) =
  `Assoc
    [
      ("id", str (Ids.Plant_id.to_string p.id));
      ("display_name", str p.display_name);
      ("aliases", `List (List.map str p.aliases));
      ("scientific_name", opt str p.scientific_name);
      ("authorship", opt str p.authorship);
      ("gbif_key", opt (fun n -> `Int n) p.gbif_key);
      ("notes", str p.notes);
      ("notes_updated_at", opt ts p.notes_updated_at);
      ( "cover_photo_id",
        opt (fun x -> str (Ids.Photo_id.to_string x)) p.cover_photo_id );
      ("created_at", ts p.created_at);
      ("updated_at", ts p.updated_at);
      ("deleted_at", opt ts p.deleted_at);
    ]

let observation_json (o : Observation.t) =
  `Assoc
    [
      ("id", str (Ids.Observation_id.to_string o.id));
      ("plant_id", opt (fun x -> str (Ids.Plant_id.to_string x)) o.plant_id);
      ("at", ts o.at);
      ( "position",
        opt
          (fun (p : Observation.position) ->
            `Assoc
              [
                ("lat", `Float p.lat);
                ("lon", `Float p.lon);
                ("accuracy_m", opt (fun a -> `Float a) p.accuracy_m);
              ])
          o.position );
      ("place_label", opt str o.place_label);
      ("place_derived", opt str o.place_derived);
      ("note", opt str o.note);
      ("created_at", ts o.created_at);
      ("updated_at", ts o.updated_at);
      ("deleted_at", opt ts o.deleted_at);
    ]

let photo_json (p : Photo.t) =
  `Assoc
    [
      ("id", str (Ids.Photo_id.to_string p.id));
      ("observation_id", str (Ids.Observation_id.to_string p.observation_id));
      ("taken_at", ts p.taken_at);
      ("width", `Int p.width);
      ("height", `Int p.height);
      ("sha256", str p.sha256);
      ("preview_path", str p.preview_path);
      ("preview_bucket_key", opt str p.preview_bucket_key);
      ( "original_target",
        str (Photo.Original_target.to_string p.original_target) );
      ("drive_file_id", opt str p.drive_file_id);
      ("upload_state", str (Photo.Upload_state.to_string p.upload_state));
      ("created_at", ts p.created_at);
      ("updated_at", ts p.updated_at);
      ("deleted_at", opt ts p.deleted_at);
    ]

let tag_json (t : Tag.t) =
  `Assoc
    [
      ("id", str (Ids.Tag_id.to_string t.id));
      ("name", str t.name);
      ("created_at", ts t.created_at);
      ("updated_at", ts t.updated_at);
      ("deleted_at", opt ts t.deleted_at);
    ]

let plant_tag_json (t : Tag.Plant_tag.t) =
  `Assoc
    [
      ("id", str (Ids.Plant_tag_id.to_string t.id));
      ("plant_id", str (Ids.Plant_id.to_string t.plant_id));
      ("tag_id", str (Ids.Tag_id.to_string t.tag_id));
      ("created_at", ts t.created_at);
      ("updated_at", ts t.updated_at);
      ("deleted_at", opt ts t.deleted_at);
    ]

let plant_t = Cli.testable_of_json plant_json
let observation_t = Cli.testable_of_json observation_json
let photo_t = Cli.testable_of_json photo_json
let tag_t = Cli.testable_of_json tag_json
let plant_tag_t = Cli.testable_of_json plant_tag_json

(* ---------- running statements ---------- *)

let write = Cli.write_ok
let writes = Cli.write_all_ok
let all = Cli.all
let find = Cli.find

let check_changes what expected db s =
  Alcotest.(check int) what expected (write what db s)

let check_fails what db s =
  match Cli.write db s with
  | Ok n -> Alcotest.failf "%s should fail, changed %d row(s)" what n
  | Error _ -> ()

let names (ps : Plant.t list) =
  List.map (fun (p : Plant.t) -> p.display_name) ps

let raw_row db sql =
  match Cli.rows db sql with
  | [row] -> row
  | rows ->
      Alcotest.failf "%S gave %d rows, expected one" sql (List.length rows)

let raw_field db ~table ~column ~id =
  Cli.field column
    (raw_row db
       (Printf.sprintf "select %s from %s where id = '%s';\n" column table id))

let raw_text db ~table ~column ~id =
  match raw_field db ~table ~column ~id with
  | `String s -> Some s
  | `Null -> None
  | other ->
      Alcotest.failf "%s.%s is %s, not text or null" table column
        (Yojson.Safe.to_string other)

let stamp t = Some (Codec.timestamp t)

(* Every upsert is "insert … on conflict … do update", never a statement that
   deletes the old row first (schema.mli). *)
let check_not_replace what (s : Stmt.t) =
  let sql = String.lowercase_ascii s.sql in
  Alcotest.(check bool)
    (what ^ " is not insert or replace")
    false
    (Cli.contains ~sub:"insert or replace" sql);
  Alcotest.(check bool)
    (what ^ " is not replace into")
    false
    (Cli.contains ~sub:"replace into" sql);
  Alcotest.(check bool)
    (what ^ " has an on conflict clause")
    true
    (Cli.contains ~sub:"on conflict" sql)

(* [upsert b] over [a], both under one id, changes 1 row and leaves exactly
   [b]; then the same with [a] over [b]. With [a] bare and [b] full, every
   column goes from null to set and back, so a column missing from the
   "do update set" list shows. *)
let check_upsert_overwrites what record ~setup ~upsert ~get a b =
  List.iter
    (fun (label, first, second) ->
      let db = Cli.migrated_db () in
      writes (what ^ " setup") db setup;
      writes (what ^ " first upsert") db [upsert first];
      check_changes
        (Printf.sprintf "%s: upserting the %s record over it changes 1 row" what
           label)
        1 db (upsert second);
      Alcotest.(check (option record))
        (Printf.sprintf "%s: get gives exactly the %s record" what label)
        (Some second)
        (find db (get second)))
    [("full", a, b); ("bare", b, a)]

(* ---------- Stmt ---------- *)

let name_query =
  Stmt.query ~json:[] (Row.col P.display_name)
    "select display_name from plants where id = ?"
    [Codec.Text (uuid 1)]

let stmt_gives_back () =
  let s = Stmt.stmt name_query in
  Alcotest.(check string)
    "stmt gives back the sql" "select display_name from plants where id = ?"
    s.sql;
  Alcotest.(check (list Cli.param))
    "stmt gives back the parameters"
    [Text (uuid 1)]
    s.params

let stmt_decode () =
  Alcotest.(check (result string Cli.codec_error))
    "a row object decodes with the query's row" (Ok "Digitale")
    (Stmt.decode name_query {|{"display_name": "Digitale"}|});
  Alcotest.(check (result string Cli.codec_error))
    "a JSON array is Invalid_row not an object"
    (Error (Invalid_row "not an object"))
    (Stmt.decode name_query "[1]");
  Alcotest.(check (result string Cli.codec_error))
    "a missing column is Row Missing" (Error (Row `Missing))
    (Stmt.decode name_query "{}")

let stmt_decode_json () =
  let q =
    Stmt.query
      ~json:[Codec.json P.aliases]
      (Row.col P.aliases) "select aliases from plants" []
  in
  Alcotest.(check (result Cli.yojson Cli.codec_error))
    "a column named in ~json is parsed from its text"
    (Ok (`List [`String "a"; `String "é"]))
    (Stmt.decode q {|{"aliases": "[\"a\",\"é\"]"}|});
  Alcotest.(check (result Cli.yojson Cli.codec_error))
    "invalid JSON text in it is Invalid_json_column"
    (Error (Invalid_json_column "aliases"))
    (Stmt.decode q {|{"aliases": "["}|})

(* ---------- Plants ---------- *)

let bare_plant = plant 0x1 "Pissenlit" ~created_at:t1 ~updated_at:t1

let full_plant =
  plant 0x2 "Rose 'Albertine', \"grimpant\""
    ~aliases:["Églantier"; "dog rose, \"wild\""; "l'églantine; -- ?"]
    ~scientific_name:"Rosa canina" ~authorship:"L." ~gbif_key:8395064
    ~notes:"Ligne 1;\nligne 2 -- pas un commentaire ?"
    ~notes_updated_at:(time "2026-10-28T14:00:05.123456+02:00")
    ~cover_photo_id:(photo_id 0xff)
    ~created_at:(time "2026-01-01T00:00:00Z")
    ~updated_at:(time "2026-10-28T12:00:05.999999Z")

let plant_row_text ~aliases =
  Yojson.Safe.to_string
    (`Assoc
       [
         ("id", `String (uuid 1));
         ("display_name", `String "x");
         ("aliases", aliases);
         ("scientific_name", `Null);
         ("authorship", `Null);
         ("gbif_key", `Null);
         ("notes", `String "");
         ("notes_updated_at", `Null);
         ("cover_photo_id", `Null);
         ("created_at", `String "2026-10-28T12:00:00.000000Z");
         ("updated_at", `String "2026-10-28T12:00:00.000000Z");
         ("deleted_at", `Null);
         ("rank", `Float (-1.5));
       ])

let decode_aliases aliases =
  Result.map
    (fun (p : Plant.t) -> p.aliases)
    (Codec.decode ~json:[] Plants.row (plant_row_text ~aliases))

let plants_row_aliases () =
  let check what expected aliases =
    Alcotest.(check (result (list string) Cli.codec_error))
      what (Ok expected) (decode_aliases aliases)
  in
  check "an array of strings is kept in order" ["b"; "a"]
    (`String "[\"b\",\"a\"]");
  check "the empty array is []" [] (`String "[]");
  check "non-string elements are dropped" ["a"; "b"]
    (`String "[\"a\",1,null,{\"x\":1},\"b\"]");
  check "an object is []" [] (`String "{\"a\":\"b\"}");
  check "a JSON string is []" [] (`String "\"x\"");
  check "a number is []" [] (`String "3");
  check "text that is not JSON is []" [] (`String "[");
  check "empty text is []" [] (`String "");
  check "an already parsed array works too" ["a"] (`List [`String "a"])

let plants_row_extra_keys () =
  Alcotest.(check (result plant_t Cli.codec_error))
    "a row with extra columns (select p.*, …) decodes"
    (Ok (plant 0x1 "x"))
    (Codec.decode ~json:[] Plants.row (plant_row_text ~aliases:(`String "[]")))

let plants_unparsable_aliases () =
  let db = Cli.migrated_db () in
  check_changes "upserting the plant changes 1 row" 1 db
    (Plants.upsert full_plant);
  Cli.exec_ok "damaged aliases" db
    (Printf.sprintf "update plants set aliases = '[' where id = '%s';\n"
       (uuid 0x2));
  Alcotest.(check (list plant_t))
    "the plant still lists, with no aliases"
    [{full_plant with aliases = []}]
    (all db Plants.list)

let plants_round_trip () =
  let db = Cli.migrated_db () in
  check_changes "upserting the full plant changes 1 row" 1 db
    (Plants.upsert full_plant);
  check_changes "upserting the bare plant changes 1 row" 1 db
    (Plants.upsert bare_plant);
  Alcotest.(check (option plant_t))
    "get gives back the bare plant" (Some bare_plant)
    (find db (Plants.get bare_plant.id));
  Alcotest.(check (option string))
    "empty aliases are stored as []" (Some "[]")
    (raw_text db ~table:"plants" ~column:"aliases" ~id:(uuid 0x1));
  Alcotest.(check (option plant_t))
    "get gives back every field of the full plant (it is live)"
    (Some full_plant)
    (find db (Plants.get full_plant.id))

let plants_round_trip_deleted () =
  let db = Cli.migrated_db () in
  let deleted = {full_plant with deleted_at = Some t3} in
  writes "upsert" db [Plants.upsert deleted];
  Alcotest.(check (option plant_t))
    "get does not return a soft-deleted plant" None
    (find db (Plants.get deleted.id));
  Alcotest.(check (option plant_t))
    "get of an absent id is None" None
    (find db (Plants.get (plant_id 0x99)));
  Alcotest.(check (option string))
    "deleted_at is stored as written" (stamp t3)
    (raw_text db ~table:"plants" ~column:"deleted_at" ~id:(uuid 0x2))

let plants_list_order () =
  let db = Cli.migrated_db () in
  writes "upserts" db
    (List.map Plants.upsert
       [
         plant 0x16 "Érable";
         plant 0x12 "Menthe";
         plant 0x11 "Menthe";
         plant 0x13 "chêne";
         plant 0x14 "bouleau";
         plant 0x15 "Aubépine";
         plant 0x17 "Zinnia";
         plant 0x18 "Ail" ~deleted_at:t1;
       ]);
  Alcotest.(check (list string))
    "live plants by display_name nocase then id; accented capital after Z"
    [
      uuid 0x15; uuid 0x14; uuid 0x13; uuid 0x11; uuid 0x12; uuid 0x17; uuid 0x16;
    ]
    (List.map
       (fun (p : Plant.t) -> Ids.Plant_id.to_string p.id)
       (all db Plants.list))

let plants_list_empty () =
  let db = Cli.migrated_db () in
  Alcotest.(check (list plant_t))
    "list of an empty table is []" [] (all db Plants.list)

let plants_upsert_in_place () =
  let db = Cli.migrated_db () in
  writes "plant and observation" db
    [
      Plants.upsert bare_plant;
      Observations.upsert (observation 0x31 t1 ~plant:0x1);
    ];
  let renamed =
    {
      bare_plant with
      display_name = "Dent-de-lion";
      aliases = ["Pissenlit"];
      updated_at = t3;
    }
  in
  check_changes "upserting an existing id changes 1 row" 1 db
    (Plants.upsert renamed);
  Alcotest.(check (option plant_t))
    "get gives the new values" (Some renamed)
    (find db (Plants.get bare_plant.id));
  Alcotest.(check int)
    "the plant's observation survives the upsert" 1
    (List.length (all db (Observations.of_plant bare_plant.id)));
  Alcotest.(check int)
    "one plants row" 1
    (Cli.count db "select count(*) as n from plants;\n")

let plants_upsert_revives () =
  let db = Cli.migrated_db () in
  writes "deleted plant" db
    [Plants.upsert {bare_plant with deleted_at = Some t1}];
  Alcotest.(check (list plant_t))
    "a deleted plant is not listed" [] (all db Plants.list);
  let revived = {bare_plant with updated_at = t3} in
  check_changes "upserting it with deleted_at = None changes 1 row" 1 db
    (Plants.upsert revived);
  Alcotest.(check (list plant_t))
    "it is listed again" [revived] (all db Plants.list)

let plants_soft_delete () =
  let db = Cli.migrated_db () in
  writes "plant, tag, link, observation" db
    [
      Plants.upsert bare_plant;
      Tags.upsert (tag 0xc1 "Jardin");
      Tags.tag ~plant:bare_plant.id ~tag:(tag_id 0xc1) ~at:t0;
      Observations.upsert (observation 0x31 t1 ~plant:0x1);
    ];
  check_changes "soft_delete of a live plant changes 1 row" 1 db
    (Plants.soft_delete bare_plant.id ~at:t2);
  check_changes "soft_delete again changes 0 rows" 0 db
    (Plants.soft_delete bare_plant.id ~at:t3);
  check_changes "soft_delete of an absent plant changes 0 rows" 0 db
    (Plants.soft_delete (plant_id 0x99) ~at:t3);
  Alcotest.(check (option string))
    "deleted_at is the first at" (stamp t2)
    (raw_text db ~table:"plants" ~column:"deleted_at" ~id:(uuid 0x1));
  Alcotest.(check (option string))
    "updated_at is the first at" (stamp t2)
    (raw_text db ~table:"plants" ~column:"updated_at" ~id:(uuid 0x1));
  Alcotest.(check (option plant_t))
    "get no longer returns it" None
    (find db (Plants.get bare_plant.id));
  Alcotest.(check int)
    "its observation stays live" 1
    (Cli.count db
       "select count(*) as n from observations where deleted_at is null;\n");
  Alcotest.(check int)
    "its tag link stays live" 1
    (Cli.count db
       "select count(*) as n from plant_tags where deleted_at is null;\n")

let plants_with_tag () =
  let db = Cli.migrated_db () in
  writes "plants, tags, links" db
    [
      Plants.upsert (plant 0x11 "Thym");
      Plants.upsert (plant 0x12 "basilic");
      Plants.upsert (plant 0x13 "Sauge");
      Plants.upsert (plant 0x14 "Romarin");
      Plants.upsert (plant 0x15 "Menthe");
      Tags.upsert (tag 0xc1 "Aromatique");
      Tags.upsert (tag 0xc2 "Jardin");
      Tags.tag ~plant:(plant_id 0x11) ~tag:(tag_id 0xc1) ~at:t0;
      Tags.tag ~plant:(plant_id 0x12) ~tag:(tag_id 0xc1) ~at:t0;
      Tags.tag ~plant:(plant_id 0x12) ~tag:(tag_id 0xc2) ~at:t0;
      Tags.tag ~plant:(plant_id 0x13) ~tag:(tag_id 0xc1) ~at:t0;
      Tags.untag ~plant:(plant_id 0x13) ~tag:(tag_id 0xc1) ~at:t1;
      Tags.tag ~plant:(plant_id 0x14) ~tag:(tag_id 0xc1) ~at:t0;
      Plants.soft_delete (plant_id 0x14) ~at:t1;
      Tags.tag ~plant:(plant_id 0x15) ~tag:(tag_id 0xc2) ~at:t0;
    ];
  Alcotest.(check (list string))
    "live plants with a live link, once each, in list order" ["basilic"; "Thym"]
    (names (all db (Plants.with_tag (tag_id 0xc1))));
  writes "deleting the tag" db [Tags.soft_delete (tag_id 0xc1) ~at:t2];
  Alcotest.(check (list string))
    "a soft-deleted tag has no plants" []
    (names (all db (Plants.with_tag (tag_id 0xc1))));
  Alcotest.(check (list string))
    "an unknown tag has no plants" []
    (names (all db (Plants.with_tag (tag_id 0xc9))))

let tags_links () =
  let db = Cli.migrated_db () in
  writes "plants, tags, links" db
    [
      Plants.upsert (plant 0x11 "Thym");
      Plants.upsert (plant 0x12 "basilic");
      Plants.upsert (plant 0x13 "Sauge");
      Plants.upsert (plant 0x14 "Romarin");
      Tags.upsert (tag 0xc1 "Aromatique");
      Tags.upsert (tag 0xc2 "Jardin");
      Tags.upsert (tag 0xc3 "Toxique");
      Tags.tag ~plant:(plant_id 0x12) ~tag:(tag_id 0xc2) ~at:t0;
      Tags.tag ~plant:(plant_id 0x11) ~tag:(tag_id 0xc1) ~at:t0;
      Tags.tag ~plant:(plant_id 0x12) ~tag:(tag_id 0xc1) ~at:t0;
      Tags.tag ~plant:(plant_id 0x13) ~tag:(tag_id 0xc1) ~at:t0;
      Tags.untag ~plant:(plant_id 0x13) ~tag:(tag_id 0xc1) ~at:t1;
      Tags.tag ~plant:(plant_id 0x14) ~tag:(tag_id 0xc1) ~at:t0;
      Plants.soft_delete (plant_id 0x14) ~at:t1;
      Tags.tag ~plant:(plant_id 0x11) ~tag:(tag_id 0xc3) ~at:t0;
      Tags.soft_delete (tag_id 0xc3) ~at:t1;
    ];
  let pairs =
    List.map
      (fun (pt : Tag.Plant_tag.t) ->
        (Ids.Tag_id.to_string pt.tag_id, Ids.Plant_id.to_string pt.plant_id))
      (all db Tags.links)
  in
  Alcotest.(check (list (pair string string)))
    "live links of live tags and plants, by tag then plant"
    [
      ( Ids.Tag_id.to_string (tag_id 0xc1),
        Ids.Plant_id.to_string (plant_id 0x11) );
      ( Ids.Tag_id.to_string (tag_id 0xc1),
        Ids.Plant_id.to_string (plant_id 0x12) );
      ( Ids.Tag_id.to_string (tag_id 0xc2),
        Ids.Plant_id.to_string (plant_id 0x12) );
    ]
    pairs

let plants_upsert_overwrites () =
  check_upsert_overwrites "Plants" plant_t ~setup:[] ~upsert:Plants.upsert
    ~get:(fun (p : Plant.t) -> Plants.get p.id)
    bare_plant
    {full_plant with id = bare_plant.id}

let plants_upsert_sql () =
  check_not_replace "Plants.upsert" (Plants.upsert full_plant)

(* ---------- Observations ---------- *)

let full_observation =
  observation 0x31
    (time "2026-03-29T09:15:00.123456+02:00")
    ~plant:0x1
    ~position:{lat = 48.0625; lon = 7.0625; accuracy_m = Some 12.5}
    ~place_label:"Lac Blanc, rive \"nord\"" ~place_derived:"Orbey; Haut-Rhin"
    ~note:"l'eau -- ? froide" ~created_at:t1 ~updated_at:t2 ~deleted_at:t3

let observations_round_trip () =
  let db = Cli.migrated_db () in
  let cases =
    [
      ( "a position with accuracy, every option set",
        {full_observation with deleted_at = None} );
      ( "a position without accuracy",
        observation 0x32 t1 ~plant:0x1
          ~position:{lat = -90.; lon = 180.; accuracy_m = None} );
      ( "a position with accuracy 0",
        observation 0x33 t1
          ~position:{lat = 0.; lon = -180.; accuracy_m = Some 0.} );
      ("no position, no plant, no option", observation 0x34 t1);
    ]
  in
  writes "plant" db [Plants.upsert bare_plant];
  List.iter
    (fun (what, (o : Observation.t)) ->
      check_changes
        (what ^ ": upsert changes 1 row")
        1 db (Observations.upsert o);
      Alcotest.(check (option observation_t))
        (what ^ ": get gives it back")
        (Some o)
        (find db (Observations.get o.id)))
    cases

let observations_no_position_nulls () =
  let db = Cli.migrated_db () in
  writes "an observation without position" db
    [Observations.upsert (observation 0x34 t1)];
  List.iter
    (fun column ->
      Alcotest.(check Cli.yojson)
        (column ^ " is written as null")
        `Null
        (raw_field db ~table:"observations" ~column ~id:(uuid 0x34)))
    ["lat"; "lon"; "accuracy_m"]

let observations_row_position () =
  let text ~lat ~lon ~accuracy =
    Yojson.Safe.to_string
      (`Assoc
         [
           ("id", `String (uuid 0x31));
           ("plant_id", `Null);
           ("at", `String "2026-10-28T12:00:00.000000Z");
           ("lat", lat);
           ("lon", lon);
           ("accuracy_m", accuracy);
           ("place_label", `Null);
           ("place_derived", `Null);
           ("note", `Null);
           ("created_at", `String "2026-10-28T12:00:00.000000Z");
           ("updated_at", `String "2026-10-28T12:00:00.000000Z");
           ("deleted_at", `Null);
         ])
  in
  let position t =
    Result.map
      (fun (o : Observation.t) -> observation_json o)
      (Codec.decode ~json:[] Observations.row t)
    |> Result.map (function
      | `Assoc kvs -> List.assoc "position" kvs
      | other -> other)
  in
  let check what expected t =
    Alcotest.(check (result Cli.yojson Cli.codec_error))
      what (Ok expected) (position t)
  in
  check "lat and lon set give a position"
    (`Assoc
       [("lat", `Float 48.); ("lon", `Float 7.5); ("accuracy_m", `Float 3.)])
    (text ~lat:(`Int 48) ~lon:(`Float 7.5) ~accuracy:(`Float 3.));
  check "an accuracy without lat and lon is dropped" `Null
    (text ~lat:`Null ~lon:`Null ~accuracy:(`Float 3.));
  check "lat without lon is no position" `Null
    (text ~lat:(`Float 48.) ~lon:`Null ~accuracy:`Null);
  check "lon without lat is no position" `Null
    (text ~lat:`Null ~lon:(`Float 7.) ~accuracy:`Null)

let observations_invalid () =
  let db = Cli.migrated_db () in
  check_fails "a latitude of 91" db
    (Observations.upsert
       (observation 0x31 t1 ~position:{lat = 91.; lon = 0.; accuracy_m = None}));
  check_fails "a negative accuracy" db
    (Observations.upsert
       (observation 0x32 t1
          ~position:{lat = 0.; lon = 0.; accuracy_m = Some (-1.)}));
  check_fails "an unknown plant" db
    (Observations.upsert (observation 0x33 t1 ~plant:0x99))

let observations_list_order () =
  let db = Cli.migrated_db () in
  writes "observations" db
    (List.map Observations.upsert
       [
         observation 0x31 t1;
         observation 0x32 t1;
         observation 0x30 t3;
         observation 0x33 t2 ~deleted_at:t3;
       ]);
  Alcotest.(check (list string))
    "live observations by at descending then id descending"
    [uuid 0x30; uuid 0x32; uuid 0x31]
    (List.map
       (fun (o : Observation.t) -> Ids.Observation_id.to_string o.id)
       (all db Observations.list))

let observations_of_plant () =
  let db = Cli.migrated_db () in
  writes "plants and observations" db
    [
      Plants.upsert bare_plant;
      Plants.upsert (plant 0x2 "Autre");
      Observations.upsert (observation 0x31 t1 ~plant:0x1);
      Observations.upsert (observation 0x32 t2 ~plant:0x1);
      Observations.upsert (observation 0x33 t3 ~plant:0x1 ~deleted_at:t3);
      Observations.upsert (observation 0x34 t1 ~plant:0x2);
      Observations.upsert (observation 0x35 t1);
      Plants.soft_delete bare_plant.id ~at:t3;
    ];
  Alcotest.(check (list string))
    "live observations of a deleted plant, newest first"
    [uuid 0x32; uuid 0x31]
    (List.map
       (fun (o : Observation.t) -> Ids.Observation_id.to_string o.id)
       (all db (Observations.of_plant bare_plant.id)))

let observations_unidentified () =
  let db = Cli.migrated_db () in
  writes "plant and observations" db
    [
      Plants.upsert bare_plant;
      Observations.upsert (observation 0x31 t1 ~plant:0x1);
      Observations.upsert (observation 0x35 t1);
      Observations.upsert (observation 0x36 t1 ~deleted_at:t3);
    ];
  Alcotest.(check (list string))
    "unidentified gives the live observations without plant"
    [uuid 0x35]
    (List.map
       (fun (o : Observation.t) -> Ids.Observation_id.to_string o.id)
       (all db Observations.unidentified))

let observations_between () =
  let db = Cli.migrated_db () in
  let from = time "2026-03-29T00:00:00Z" in
  let until = time "2026-03-30T00:00:00Z" in
  writes "observations around a day" db
    (List.map Observations.upsert
       [
         observation 0x31 (time "2026-03-28T23:59:59.999999Z");
         observation 0x32 from;
         observation 0x33 (time "2026-03-29T23:59:59.999999Z");
         observation 0x34 until;
         observation 0x35 (time "2026-03-29T12:00:00Z") ~deleted_at:t3;
       ]);
  let ids q =
    List.map
      (fun (o : Observation.t) -> Ids.Observation_id.to_string o.id)
      (all db q)
  in
  Alcotest.(check (list string))
    "from is included, until excluded, deleted ignored, newest first"
    [uuid 0x33; uuid 0x32]
    (ids (Observations.between ~from ~until));
  Alcotest.(check (list string))
    "bounds given with an offset are the same instants"
    [uuid 0x33; uuid 0x32]
    (ids
       (Observations.between
          ~from:(time "2026-03-29T02:00:00+02:00")
          ~until:(time "2026-03-30T02:00:00+02:00")));
  Alcotest.(check (list string))
    "until = from is empty" []
    (ids (Observations.between ~from ~until:from));
  Alcotest.(check (list string))
    "until < from is empty" []
    (ids (Observations.between ~from:until ~until:from))

let observations_soft_delete () =
  let db = Cli.migrated_db () in
  writes "observation" db [Observations.upsert (observation 0x31 t1)];
  check_changes "soft_delete of a live observation changes 1 row" 1 db
    (Observations.soft_delete (observation_id 0x31) ~at:t2);
  check_changes "soft_delete again changes 0 rows" 0 db
    (Observations.soft_delete (observation_id 0x31) ~at:t3);
  check_changes "soft_delete of an absent observation changes 0 rows" 0 db
    (Observations.soft_delete (observation_id 0x99) ~at:t3);
  Alcotest.(check (option string))
    "deleted_at is the first at" (stamp t2)
    (raw_text db ~table:"observations" ~column:"deleted_at" ~id:(uuid 0x31));
  Alcotest.(check (option string))
    "updated_at is the first at" (stamp t2)
    (raw_text db ~table:"observations" ~column:"updated_at" ~id:(uuid 0x31));
  Alcotest.(check (option observation_t))
    "get no longer returns it" None
    (find db (Observations.get (observation_id 0x31)));
  Alcotest.(check (option observation_t))
    "get of an absent id is None" None
    (find db (Observations.get (observation_id 0x99)))

let observations_upsert_overwrites () =
  check_upsert_overwrites "Observations" observation_t
    ~setup:[Plants.upsert bare_plant]
    ~upsert:Observations.upsert
    ~get:(fun (o : Observation.t) -> Observations.get o.id)
    (observation 0x31 t1)
    {full_observation with deleted_at = None}

let observations_upsert_sql () =
  check_not_replace "Observations.upsert" (Observations.upsert full_observation)

(* ---------- Tags ---------- *)

(* Python uuid.uuid5 of "plant_tags/<plant 0a>/<tag c1>" under the Herbier
   namespace *)
let link_id_a_c1 = "643fde24-732d-5b5d-865c-8caca18b4fcb"

let link_row db =
  match
    Cli.rows db
      (Printf.sprintf
         "select * from plant_tags where plant_id = '%s' and tag_id = '%s';\n"
         (uuid 0xa) (uuid 0xc1))
  with
  | [] -> None
  | [row] -> (
      match
        Codec.decode ~json:[] Tags.plant_tag_row (Yojson.Safe.to_string row)
      with
      | Ok v -> Some v
      | Error e ->
          Alcotest.failf "decoding a plant_tags row: %s"
            (Cli.string_of_codec_error e))
  | _ -> Alcotest.fail "two plant_tags rows for one pair"

let link_of ~created_at ~updated_at ?deleted_at id : Tag.Plant_tag.t =
  {
    id;
    plant_id = plant_id 0xa;
    tag_id = tag_id 0xc1;
    created_at;
    updated_at;
    deleted_at;
  }

let vector_id =
  match Ids.Plant_tag_id.of_string link_id_a_c1 with
  | Some x -> x
  | None -> invalid_arg "fixture vector id"

let with_plant_and_tag () =
  let db = Cli.migrated_db () in
  writes "plant 0a and tag c1" db
    [Plants.upsert (plant 0xa "Thym"); Tags.upsert (tag 0xc1 "Aromatique")];
  db

let tags_round_trip () =
  let db = Cli.migrated_db () in
  let t =
    tag 0xc1 "Plantes d'ombre, \"humides\"" ~created_at:t1 ~updated_at:t2
  in
  check_changes "upsert changes 1 row" 1 db (Tags.upsert t);
  Alcotest.(check (option tag_t))
    "get gives it back" (Some t)
    (find db (Tags.get t.id));
  writes "deleting it" db [Tags.upsert {t with deleted_at = Some t3}];
  Alcotest.(check (option tag_t))
    "get of a deleted tag is None" None
    (find db (Tags.get t.id))

let tags_list_order () =
  let db = Cli.migrated_db () in
  writes "tags" db
    (List.map Tags.upsert
       [
         tag 0xc3 "jardin";
         tag 0xc2 "Jardin";
         tag 0xc1 "Bois";
         tag 0xc4 "Été";
         tag 0xc5 "zone humide";
         tag 0xc6 "Abandonné" ~deleted_at:t1;
       ]);
  Alcotest.(check (list string))
    "live tags by name nocase then id"
    ["Bois"; "Jardin"; "jardin"; "zone humide"; "Été"]
    (List.map (fun (t : Tag.t) -> t.name) (all db Tags.list))

let tags_tag_inserts () =
  let db = with_plant_and_tag () in
  check_changes "tag on a new pair changes 1 row" 1 db
    (Tags.tag ~plant:(plant_id 0xa) ~tag:(tag_id 0xc1) ~at:t1);
  Alcotest.(check (option plant_tag_t))
    "the row has the of_key id, created_at = updated_at = at, no deleted_at"
    (Some (link_of vector_id ~created_at:t1 ~updated_at:t1))
    (link_row db);
  check_changes "tag on a live link changes 0 rows" 0 db
    (Tags.tag ~plant:(plant_id 0xa) ~tag:(tag_id 0xc1) ~at:t2);
  Alcotest.(check (option plant_tag_t))
    "updated_at is not bumped on a live link"
    (Some (link_of vector_id ~created_at:t1 ~updated_at:t1))
    (link_row db)

let tags_untag_and_revive () =
  let db = with_plant_and_tag () in
  writes "tag" db [Tags.tag ~plant:(plant_id 0xa) ~tag:(tag_id 0xc1) ~at:t1];
  check_changes "untag of a live link changes 1 row" 1 db
    (Tags.untag ~plant:(plant_id 0xa) ~tag:(tag_id 0xc1) ~at:t2);
  Alcotest.(check (option plant_tag_t))
    "untag sets deleted_at and updated_at to at"
    (Some (link_of vector_id ~created_at:t1 ~updated_at:t2 ~deleted_at:t2))
    (link_row db);
  check_changes "untag again changes 0 rows" 0 db
    (Tags.untag ~plant:(plant_id 0xa) ~tag:(tag_id 0xc1) ~at:t3);
  check_changes "tag on a deleted link changes 1 row" 1 db
    (Tags.tag ~plant:(plant_id 0xa) ~tag:(tag_id 0xc1) ~at:t3);
  Alcotest.(check (option plant_tag_t))
    "the revived row keeps id and created_at, updated_at = at"
    (Some (link_of vector_id ~created_at:t1 ~updated_at:t3))
    (link_row db);
  Alcotest.(check int)
    "still one plant_tags row" 1
    (Cli.count db "select count(*) as n from plant_tags;\n")

let tags_untag_absent () =
  let db = with_plant_and_tag () in
  check_changes "untag with no link changes 0 rows" 0 db
    (Tags.untag ~plant:(plant_id 0xa) ~tag:(tag_id 0xc1) ~at:t1)

let tags_tag_unknown () =
  let db = with_plant_and_tag () in
  check_fails "tag on an unknown plant" db
    (Tags.tag ~plant:(plant_id 0x99) ~tag:(tag_id 0xc1) ~at:t1);
  check_fails "tag with an unknown tag" db
    (Tags.tag ~plant:(plant_id 0xa) ~tag:(tag_id 0xc9) ~at:t1)

let tags_upsert_plant_tag () =
  let db = with_plant_and_tag () in
  let fresh = link_of (plant_tag_id 0xd1) ~created_at:t1 ~updated_at:t1 in
  check_changes "upsert_plant_tag of a new pair changes 1 row" 1 db
    (Tags.upsert_plant_tag fresh);
  Alcotest.(check (option plant_tag_t))
    "the new row is the record as given" (Some fresh) (link_row db);
  let other =
    link_of (plant_tag_id 0xd2) ~created_at:t2 ~updated_at:t3 ~deleted_at:t3
  in
  check_changes "upsert_plant_tag on an existing pair changes 1 row" 1 db
    (Tags.upsert_plant_tag other);
  Alcotest.(check (option plant_tag_t))
    "id and created_at kept, updated_at and deleted_at from the record"
    (Some
       (link_of (plant_tag_id 0xd1) ~created_at:t1 ~updated_at:t3 ~deleted_at:t3))
    (link_row db);
  check_not_replace "Tags.upsert_plant_tag" (Tags.upsert_plant_tag other)

let tags_of_plant () =
  let db = Cli.migrated_db () in
  writes "plant, tags, links" db
    [
      Plants.upsert (plant 0xa "Thym");
      Tags.upsert (tag 0xc1 "Jardin");
      Tags.upsert (tag 0xc2 "aromatique");
      Tags.upsert (tag 0xc3 "Sec");
      Tags.upsert (tag 0xc4 "Bord de route");
      Tags.tag ~plant:(plant_id 0xa) ~tag:(tag_id 0xc1) ~at:t0;
      Tags.tag ~plant:(plant_id 0xa) ~tag:(tag_id 0xc2) ~at:t0;
      Tags.tag ~plant:(plant_id 0xa) ~tag:(tag_id 0xc3) ~at:t0;
      Tags.untag ~plant:(plant_id 0xa) ~tag:(tag_id 0xc3) ~at:t1;
      Tags.tag ~plant:(plant_id 0xa) ~tag:(tag_id 0xc4) ~at:t0;
      Tags.soft_delete (tag_id 0xc4) ~at:t1;
    ];
  Alcotest.(check (list string))
    "live tags with a live link, by name" ["aromatique"; "Jardin"]
    (List.map
       (fun (t : Tag.t) -> t.name)
       (all db (Tags.of_plant (plant_id 0xa))));
  Alcotest.(check int)
    "soft-deleting a tag leaves its links as they are (3 live links)" 3
    (Cli.count db
       "select count(*) as n from plant_tags where deleted_at is null;\n")

let tags_soft_delete () =
  let db = Cli.migrated_db () in
  writes "tag" db [Tags.upsert (tag 0xc1 "Jardin")];
  check_changes "soft_delete of a live tag changes 1 row" 1 db
    (Tags.soft_delete (tag_id 0xc1) ~at:t1);
  check_changes "soft_delete again changes 0 rows" 0 db
    (Tags.soft_delete (tag_id 0xc1) ~at:t2);
  check_changes "soft_delete of an absent tag changes 0 rows" 0 db
    (Tags.soft_delete (tag_id 0xc9) ~at:t2);
  Alcotest.(check (option string))
    "deleted_at is the first at" (stamp t1)
    (raw_text db ~table:"tags" ~column:"deleted_at" ~id:(uuid 0xc1));
  Alcotest.(check (option string))
    "updated_at is the first at" (stamp t1)
    (raw_text db ~table:"tags" ~column:"updated_at" ~id:(uuid 0xc1));
  Alcotest.(check (option tag_t))
    "get of an absent id is None" None
    (find db (Tags.get (tag_id 0xc9)))

let tags_upsert_overwrites () =
  check_upsert_overwrites "Tags" tag_t ~setup:[] ~upsert:Tags.upsert
    ~get:(fun (t : Tag.t) -> Tags.get t.id)
    (tag 0xc1 "Jardin")
    (tag 0xc1 "Plantes d'ombre" ~created_at:t1 ~updated_at:t2)

let tags_upsert_sql () =
  check_not_replace "Tags.upsert" (Tags.upsert (tag 0xc1 "x"))

(* ---------- Photos ---------- *)

let full_photo =
  photo 0xf1 ~observation:0x31
    (time "2026-03-29T09:15:00.000001+02:00")
    ~preview_bucket_key:"u/1/p.webp"
    ~original_target:Photo.Original_target.App_only ~drive_file_id:"1AbC-d'e"
    ~upload_state:Photo.Upload_state.Original_missing ~created_at:t1
    ~updated_at:t2

let photos_round_trip () =
  let db = Cli.migrated_db () in
  writes "observation" db [Observations.upsert (observation 0x31 t1)];
  List.iter
    (fun (what, (p : Photo.t)) ->
      check_changes (what ^ ": upsert changes 1 row") 1 db (Photos.upsert p);
      Alcotest.(check (option photo_t))
        (what ^ ": get gives it back")
        (Some p)
        (find db (Photos.get p.id)))
    [
      ("every option set", full_photo);
      ("no option set", photo 0xf2 ~observation:0x31 t1);
      ( "uploaded",
        photo 0xf3 ~observation:0x31 t1
          ~upload_state:Photo.Upload_state.Uploaded );
      ( "failed",
        photo 0xf4 ~observation:0x31 t1 ~upload_state:Photo.Upload_state.Failed
      );
    ];
  check_not_replace "Photos.upsert" (Photos.upsert full_photo)

let photo_ids ps =
  List.map (fun (p : Photo.t) -> Ids.Photo_id.to_string p.id) ps

let photos_lists () =
  let db = Cli.migrated_db () in
  writes "plants, observations, photos" db
    [
      Plants.upsert (plant 0x1 "A");
      Plants.upsert (plant 0x2 "B");
      Observations.upsert (observation 0x31 t1 ~plant:0x1);
      Observations.upsert (observation 0x32 t1 ~plant:0x1);
      Observations.upsert (observation 0x33 t1 ~plant:0x2);
      Observations.upsert (observation 0x34 t1);
      Photos.upsert (photo 0xf2 ~observation:0x31 t2);
      Photos.upsert (photo 0xf7 ~observation:0x34 t2);
      Photos.upsert (photo 0xf1 ~observation:0x31 t1);
      Photos.upsert (photo 0xf6 ~observation:0x31 t1);
      Photos.upsert (photo 0xf4 ~observation:0x31 t0 ~deleted_at:t3);
      Photos.upsert (photo 0xf3 ~observation:0x32 t3);
      Photos.upsert (photo 0xf5 ~observation:0x33 t3);
      Observations.soft_delete (observation_id 0x32) ~at:t3;
    ];
  Alcotest.(check (list string))
    "of_observation: live photos by taken_at then id"
    [uuid 0xf1; uuid 0xf6; uuid 0xf2]
    (photo_ids (all db (Photos.of_observation (observation_id 0x31))));
  Alcotest.(check (list string))
    "of_plant: live photos of live observations, newest first, id descending"
    [uuid 0xf2; uuid 0xf6; uuid 0xf1]
    (photo_ids (all db (Photos.of_plant (plant_id 0x1))));
  Alcotest.(check (list string))
    "live: live photos of live observations, with or without a plant, newest \
     first, id descending"
    [uuid 0xf5; uuid 0xf7; uuid 0xf2; uuid 0xf6; uuid 0xf1]
    (photo_ids (all db Photos.live));
  Alcotest.(check (list string))
    "of_observation of an observation without photos is []" []
    (photo_ids (all db (Photos.of_observation (observation_id 0x99))))

let photos_soft_delete () =
  let db = Cli.migrated_db () in
  writes "observation and photo" db
    [
      Observations.upsert (observation 0x31 t1);
      Photos.upsert (photo 0xf1 ~observation:0x31 t1);
    ];
  check_changes "soft_delete of a live photo changes 1 row" 1 db
    (Photos.soft_delete (photo_id 0xf1) ~at:t2);
  check_changes "soft_delete again changes 0 rows" 0 db
    (Photos.soft_delete (photo_id 0xf1) ~at:t3);
  check_changes "soft_delete of an absent photo changes 0 rows" 0 db
    (Photos.soft_delete (photo_id 0x99) ~at:t3);
  Alcotest.(check (option string))
    "deleted_at is the first at" (stamp t2)
    (raw_text db ~table:"photos" ~column:"deleted_at" ~id:(uuid 0xf1));
  Alcotest.(check (option string))
    "updated_at is the first at" (stamp t2)
    (raw_text db ~table:"photos" ~column:"updated_at" ~id:(uuid 0xf1));
  Alcotest.(check (option photo_t))
    "get no longer returns it" None
    (find db (Photos.get (photo_id 0xf1)));
  Alcotest.(check (option photo_t))
    "get of an absent id is None" None
    (find db (Photos.get (photo_id 0x99)))

let photos_upsert_overwrites () =
  check_upsert_overwrites "Photos" photo_t
    ~setup:[Observations.upsert (observation 0x31 t1)]
    ~upsert:Photos.upsert
    ~get:(fun (p : Photo.t) -> Photos.get p.id)
    (photo 0xf1 ~observation:0x31 t1)
    full_photo

(* ---------- Settings ---------- *)

let settings_names () =
  Alcotest.(check string)
    "Storage_target is stored as storage_target" "storage_target"
    (Settings.name Settings.Storage_target);
  Alcotest.(check string)
    "Wifi_only is stored as wifi_only" "wifi_only"
    (Settings.name Settings.Wifi_only)

let stored_value db key =
  match
    Cli.rows db
      (Printf.sprintf "select value from settings where key = '%s';\n" key)
  with
  | [] -> None
  | [row] -> Some (Cli.string_field "value" row)
  | _ -> Alcotest.failf "two settings rows for %s" key

let settings_absent () =
  let db = Cli.migrated_db () in
  Alcotest.(check (option bool))
    "Wifi_only never set is None" None
    (find db (Settings.get Settings.Wifi_only));
  Alcotest.(check (option string))
    "Storage_target never set is None" None
    (Option.map Photo.Original_target.to_string
       (find db (Settings.get Settings.Storage_target)))

let settings_wifi_only () =
  let db = Cli.migrated_db () in
  check_changes "set Wifi_only true changes 1 row" 1 db
    (Settings.set Settings.Wifi_only true);
  Alcotest.(check (option bool))
    "get Wifi_only is Some true" (Some true)
    (find db (Settings.get Settings.Wifi_only));
  Alcotest.(check (option string))
    "true is stored as \"true\"" (Some "true")
    (stored_value db "wifi_only");
  check_changes "set Wifi_only false changes 1 row" 1 db
    (Settings.set Settings.Wifi_only false);
  Alcotest.(check (option bool))
    "the second set replaces the value" (Some false)
    (find db (Settings.get Settings.Wifi_only));
  Alcotest.(check (option string))
    "false is stored as \"false\"" (Some "false")
    (stored_value db "wifi_only")

let settings_storage_target () =
  let db = Cli.migrated_db () in
  List.iter
    (fun (target, label) ->
      check_changes
        ("set Storage_target " ^ label ^ " changes 1 row")
        1 db
        (Settings.set Settings.Storage_target target);
      Alcotest.(check (option string))
        ("get Storage_target gives back " ^ label)
        (Some label)
        (Option.map Photo.Original_target.to_string
           (find db (Settings.get Settings.Storage_target)));
      Alcotest.(check (option string))
        (label ^ " is stored as its enum label")
        (Some label)
        (stored_value db "storage_target"))
    [(Photo.Original_target.Drive, "drive"); (App_only, "app_only")];
  Alcotest.(check (option bool))
    "setting Storage_target leaves Wifi_only unset" None
    (find db (Settings.get Settings.Wifi_only))

let settings_bad_value () =
  let db = Cli.migrated_db () in
  Cli.exec_ok "bad settings rows" db
    "insert into settings (key, value) values ('wifi_only', 'yes');\n\
     insert into settings (key, value) values ('storage_target', 'cloud');\n";
  Alcotest.(check (result (option bool) Cli.codec_error))
    "Wifi_only holding \"yes\" is Row WrongType" (Error (Row `WrongType))
    (Cli.find_result db (Settings.get Settings.Wifi_only));
  Alcotest.(check (result (option string) Cli.codec_error))
    "Storage_target holding an unknown label is Row WrongType"
    (Error (Row `WrongType))
    (Result.map
       (Option.map Photo.Original_target.to_string)
       (Cli.find_result db (Settings.get Settings.Storage_target)))

(* ---------- Search.match_expression ---------- *)

let match_expression () =
  List.iter
    (fun (input, expected) ->
      Alcotest.(check (option string))
        (Printf.sprintf "match_expression %S" input)
        expected
        (Search.match_expression input))
    [
      ("digitale", Some "\"digital\"*");
      ("Digitale pourpre", Some "\"digital\"* \"pourpr\"*");
      ("", None);
      ("  ", None);
      ("-'\"*", None);
      ("\t\n:()", None);
      ("rosa", Some "\"rosa\"*");
      ("NOT", Some "\"not\"*");
      ("Épervière", Some "\"epervier\"*");
      ("digitalis", Some "\"digital\"*");
      ("DIGITALE", Some "\"digital\"*");
      ("digitalé", Some "\"digital\"*");
      ("digitales", Some "\"digital\"*");
      ("digit", Some "\"digit\"*");
      ("lis", Some "\"lis\"*");
      ("rose", Some "\"rose\"*");
      ("sapins", Some "\"sapin\"*");
      ("chênes", Some "\"chen\"*");
      ("rose-trémière", Some "\"rose\"* \"tremier\"*");
      ("l'aubépine", Some "\"l\"* \"aubepin\"*");
      ("a OR b", Some "\"a\"* \"or\"* \"b\"*");
      ("NEAR(x y)", Some "\"near\"* \"x\"* \"y\"*");
      ("foo\"bar", Some "\"foo\"* \"bar\"*");
      ("col:val*", Some "\"col\"* \"val\"*");
      ("  digitale   pourpre  ", Some "\"digital\"* \"pourpr\"*");
      ("2026", Some "\"2026\"*");
      ("ÇÀ", Some "\"ca\"*");
      ("œillet", Some "\"œillet\"*");
      ("quercus", Some "\"querc\"*");
      ("trifolium", Some "\"trifoli\"*");
      ("plantae", Some "\"plant\"*");
      ("canina", Some "\"canin\"*");
      ("salici", Some "\"salic\"*");
      ("roses", Some "\"rose\"*");
      ("où", Some "\"ou\"*");
      ("OÙ", Some "\"ou\"*");
      ("straße", Some "\"straß\"*");
      ("ŸŸŸŸ", Some "\"yyyy\"*");
      ("ab\xc3", Some "\"ab\xc3\"*");
      ("«", None);
      ("’", None);
      ("—", None);
      ("« » … 🌹", None);
      ("digitale…", Some "\"digital\"*");
      ("l’épervière", Some "\"l\"* \"epervier\"*");
      ("digitales\xc2\xa0pourpres", Some "\"digital\"* \"pourpr\"*");
      ("ortie\xe2\x80\xaf!", Some "\"orti\"*");
      ("µm", Some "\"µm\"*");
      ("ệ", Some "\"ệ\"*");
      ("नीम", Some "\"नीम\"*");
      ("x⁴", Some "\"x\"*");
    ];
  (* Each Latin-1 letter with a diacritic, small and capital, folds to its base
     letter inside a word. *)
  List.iter
    (fun (letters, base) ->
      List.iter
        (fun letter ->
          Alcotest.(check (option string))
            (Printf.sprintf "%s folds to %c" letter base)
            (Some (Printf.sprintf "\"x%cxyz\"*" base))
            (Search.match_expression ("x" ^ letter ^ "xyz")))
        letters)
    [
      (["à"; "á"; "â"; "ã"; "ä"; "å"; "À"; "Á"; "Â"; "Ã"; "Ä"; "Å"], 'a');
      (["ç"; "Ç"], 'c');
      (["è"; "é"; "ê"; "ë"; "È"; "É"; "Ê"; "Ë"], 'e');
      (["ì"; "í"; "î"; "ï"; "Ì"; "Í"; "Î"; "Ï"], 'i');
      (["ñ"; "Ñ"], 'n');
      (["ò"; "ó"; "ô"; "õ"; "ö"; "Ò"; "Ó"; "Ô"; "Õ"; "Ö"], 'o');
      (["ù"; "ú"; "û"; "ü"; "Ù"; "Ú"; "Û"; "Ü"], 'u');
      (["ý"; "ÿ"; "Ý"; "Ÿ"], 'y');
    ]

(* ---------- Search over the FTS index ---------- *)

let digitale =
  plant 0xd1 "Digitale pourpre" ~scientific_name:"Digitalis purpurea"
    ~authorship:"L." ~gbif_key:5414995
    ~aliases:["Gantelée"; "Gant de bergère"]

let digitalis = plant 0xd2 "Digitalis"
let eglantier = plant 0xd3 "Églantier" ~scientific_name:"Rosa canina"

let search db text =
  match Search.plants text with
  | None -> Alcotest.failf "Search.plants %S is None" text
  | Some q -> names (all db q)

let check_search what db text expected =
  Alcotest.(check (list string)) what expected (search db text)

let done_texts =
  [
    "digitale";
    "Digitale";
    "DIGITALE";
    "digitalé";
    "digitales";
    "digitalis";
    "digit";
  ]

let check_done what db =
  List.iter
    (fun text ->
      check_search
        (Printf.sprintf "%s: %S finds Digitale pourpre and Digitalis" what text)
        db text
        ["Digitale pourpre"; "Digitalis"])
    done_texts

let three_plants_db () =
  let db = Cli.migrated_db () in
  writes "three plants" db
    (List.map Plants.upsert [eglantier; digitalis; digitale]);
  db

let search_done () = check_done "after Plants.upsert" (three_plants_db ())

let search_blank () =
  List.iter
    (fun text ->
      Alcotest.(check bool)
        (Printf.sprintf "Search.plants %S is None" text)
        true
        (Option.is_none (Search.plants text)))
    [""; "   "; "-'\"*"]

let search_fields () =
  let db = three_plants_db () in
  check_search "an alias is found" db "gantelée" ["Digitale pourpre"];
  check_search "an alias is found without its accent" db "gantelee"
    ["Digitale pourpre"];
  check_search "a scientific name is found" db "purpurea" ["Digitale pourpre"];
  check_search "a scientific name is found for another plant" db "canina"
    ["Églantier"];
  check_search "a display name with a leading accent is found" db "eglantier"
    ["Églantier"];
  check_search "every term must match" db "digitale pourpre"
    ["Digitale pourpre"];
  check_search "terms may match in different fields" db "gant purpurea"
    ["Digitale pourpre"];
  check_search "no match is []" db "chenopode" []

let search_keywords () =
  let db = three_plants_db () in
  List.iter
    (fun text ->
      check_search (Printf.sprintf "%S is plain text" text) db text [])
    ["NOT"; "OR"; "AND"; "NEAR"; "\"unterminated"; "a:b"; "x*y"];
  check_search "a quoted word is the word" db "\"digitale\""
    ["Digitale pourpre"; "Digitalis"]

let search_order () =
  let db = Cli.migrated_db () in
  writes "plants sharing an alias" db
    (List.map Plants.upsert
       [
         plant 0x13 "Érable" ~aliases:["commune"];
         plant 0x12 "Zinnia" ~aliases:["commune"];
         plant 0x11 "aubépine" ~aliases:["commune"];
         plant 0x14 "Bouleau";
       ]);
  check_search "results come in Plants.list order" db "commune"
    ["aubépine"; "Zinnia"; "Érable"]

let search_soft_delete_and_rename () =
  let db = three_plants_db () in
  writes "soft delete" db [Plants.soft_delete digitalis.id ~at:t1];
  check_search "a soft-deleted plant is not found" db "digitale"
    ["Digitale pourpre"];
  writes "revive" db [Plants.upsert {digitalis with updated_at = t2}];
  check_search "an upsert with deleted_at = None makes it searchable again" db
    "digitale"
    ["Digitale pourpre"; "Digitalis"];
  writes "rename" db
    [
      Plants.upsert
        {digitalis with display_name = "Gant de Notre-Dame"; updated_at = t3};
    ];
  check_search "a renamed plant is no longer found by its old name" db
    "digitale" ["Digitale pourpre"];
  check_search "a renamed plant is found by its new name" db "notre"
    ["Gant de Notre-Dame"];
  Cli.exec_ok "hard delete" db
    (Cli.fk_on
    ^ Printf.sprintf "delete from plants where id = '%s';\n" (uuid 0xd3));
  check_search "a hard-deleted plant is not found" db "canina" []

let search_tags () =
  let db = three_plants_db () in
  let jardin = tag 0xc1 "Jardin d'été" in
  writes "tag" db
    [Tags.upsert jardin; Tags.tag ~plant:eglantier.id ~tag:jardin.id ~at:t1];
  check_search "a live tag's name finds the plant" db "jardin" ["Églantier"];
  check_search "a tag name is folded too" db "ete" ["Églantier"];
  writes "rename tag" db
    [Tags.upsert {jardin with name = "Haie"; updated_at = t2}];
  check_search "a renamed tag no longer finds by its old name" db "jardin" [];
  check_search "a renamed tag finds by its new name" db "haie" ["Églantier"];
  writes "untag" db [Tags.untag ~plant:eglantier.id ~tag:jardin.id ~at:t2];
  check_search "untag removes the tag from the plant's document" db "haie" [];
  writes "tag again" db [Tags.tag ~plant:eglantier.id ~tag:jardin.id ~at:t3];
  check_search "tagging again brings it back" db "haie" ["Églantier"];
  writes "soft-delete tag" db [Tags.soft_delete jardin.id ~at:t3];
  check_search "a soft-deleted tag no longer finds the plant" db "haie" [];
  writes "revive tag" db
    [Tags.upsert {jardin with name = "Haie"; updated_at = t3}];
  check_search "a revived tag finds the plant again" db "haie" ["Églantier"];
  Cli.exec_ok "hard delete tag" db
    (Cli.fk_on
    ^ Printf.sprintf "delete from tags where id = '%s';\n" (uuid 0xc1));
  check_search "a hard-deleted tag no longer finds the plant" db "haie" []

let search_places () =
  let db = three_plants_db () in
  let labelled =
    observation 0x31 t1 ~plant:0xd3 ~place_label:"Col de la Schlucht"
  in
  let derived = observation 0x32 t2 ~plant:0xd3 ~place_derived:"Munster" in
  writes "observations" db
    [
      Observations.upsert labelled;
      Observations.upsert derived;
      Observations.upsert
        (observation 0x33 t3 ~plant:0xd3 ~place_label:"Col de la Schlucht");
      Observations.upsert (observation 0x34 t3 ~place_label:"Ribeauvillé");
    ];
  check_search "a place_label finds the plant, once" db "schlucht" ["Églantier"];
  check_search "a place_derived finds the plant" db "munster" ["Églantier"];
  check_search "an unidentified observation's place finds nothing" db
    "ribeauville" [];
  writes "soft-delete observations" db
    [
      Observations.soft_delete labelled.id ~at:t3;
      Observations.soft_delete (observation_id 0x33) ~at:t3;
    ];
  check_search "a soft-deleted observation's place no longer finds" db
    "schlucht" [];
  writes "move the observation" db
    [
      Observations.upsert
        {derived with plant_id = Some digitale.id; updated_at = t3};
    ];
  check_search "an observation moved to another plant follows it" db "munster"
    ["Digitale pourpre"];
  Cli.exec_ok "hard delete observation" db
    (Printf.sprintf "delete from observations where id = '%s';\n" (uuid 0x32));
  check_search "a hard-deleted observation's place no longer finds" db "munster"
    []

let search_once () =
  let db = three_plants_db () in
  let t = tag 0xc1 "Digitale" in
  writes "tag and observation matching too" db
    [
      Tags.upsert t;
      Tags.tag ~plant:digitale.id ~tag:t.id ~at:t1;
      Observations.upsert
        (observation 0x31 t1 ~plant:0xd1 ~place_label:"Digitales du col");
      Observations.upsert
        (observation 0x32 t2 ~plant:0xd1 ~place_label:"Digitales du col");
    ];
  check_search "a plant matching in several fields is returned once" db
    "digitale"
    ["Digitale pourpre"; "Digitalis"]

let search_backfill () =
  let db = Cli.fresh_db () in
  (match Schema.migrations with
  | m :: _ -> Cli.apply_migrations db [m]
  | [] -> Alcotest.fail "no migration");
  writes "plants at version 1" db
    [
      Plants.upsert digitale;
      Plants.upsert {bare_plant with deleted_at = Some t1};
    ];
  Cli.migrate db ~current:1;
  check_search "a plant inserted at version 1 is searchable after migration 2"
    db "digitale" ["Digitale pourpre"];
  check_search "a plant deleted at version 1 is not indexed" db "pissenlit" []

(* ---------- Dev_seed ---------- *)

let seed_ids_prefix () =
  let check what ids =
    List.iter
      (fun id ->
        Alcotest.(check bool)
          (Printf.sprintf "%s id %s starts with 5eed" what id)
          true
          (String.starts_with ~prefix:"5eed" id))
      ids
  in
  check "plant"
    (List.map
       (fun (p : Plant.t) -> Ids.Plant_id.to_string p.id)
       Dev_seed.plants);
  check "tag"
    (List.map (fun (t : Tag.t) -> Ids.Tag_id.to_string t.id) Dev_seed.tags);
  check "observation"
    (List.map
       (fun (o : Observation.t) -> Ids.Observation_id.to_string o.id)
       Dev_seed.observations)

let distinct_count xs = List.length (List.sort_uniq String.compare xs)
let has_any_of chars s = List.exists (fun c -> Cli.contains ~sub:c s) chars
let diacritics = ["é"; "è"; "ê"; "â"; "ï"]

let seed_plants () =
  let ps = Dev_seed.plants in
  Alcotest.(check int) "12 plants" 12 (List.length ps);
  Alcotest.(check int)
    "distinct plant ids" 12
    (distinct_count
       (List.map (fun (p : Plant.t) -> Ids.Plant_id.to_string p.id) ps));
  Alcotest.(check int) "distinct display names" 12 (distinct_count (names ps));
  Alcotest.(check bool)
    "every plant is live" true
    (List.for_all (fun (p : Plant.t) -> Option.is_none p.deleted_at) ps);
  (match
     List.find_opt (fun (p : Plant.t) -> p.display_name = "Digitale pourpre") ps
   with
  | None -> Alcotest.fail "no Digitale pourpre in the seed"
  | Some p ->
      Alcotest.(check (option string))
        "Digitale pourpre is Digitalis purpurea" (Some "Digitalis purpurea")
        p.scientific_name;
      Alcotest.(check (option string))
        "its authorship is L." (Some "L.") p.authorship;
      Alcotest.(check (option int))
        "its gbif_key is 5414995" (Some 5414995) p.gbif_key;
      Alcotest.(check bool)
        "its aliases include Gantelée" true
        (List.mem "Gantelée" p.aliases));
  (match
     List.find_opt (fun (p : Plant.t) -> p.display_name = "Digitalis") ps
   with
  | None -> Alcotest.fail "no Digitalis in the seed"
  | Some p ->
      Alcotest.(check (option string))
        "Digitalis is a free-name plant" None p.scientific_name);
  Alcotest.(check bool)
    "at least two names carry a diacritic" true
    (List.length (List.filter (has_any_of diacritics) (names ps)) >= 2)

let seed_tags () =
  let seed = Dev_seed.tags in
  Alcotest.(check bool) "at least 4 tags" true (List.length seed >= 4);
  Alcotest.(check int)
    "distinct tag names" (List.length seed)
    (distinct_count (List.map (fun (t : Tag.t) -> t.name) seed));
  Alcotest.(check bool)
    "every tag is live" true
    (List.for_all (fun (t : Tag.t) -> Option.is_none t.deleted_at) seed);
  Alcotest.(check bool)
    "a tag name carries a diacritic" true
    (List.exists (fun (t : Tag.t) -> has_any_of diacritics t.name) seed)

let seed_plant_tags () =
  let links = Dev_seed.plant_tags in
  Alcotest.(check bool) "there are plant tags" true (links <> []);
  List.iter
    (fun (l : Tag.Plant_tag.t) ->
      Alcotest.(check string)
        (Printf.sprintf "link %s has the of_key id"
           (Ids.Plant_tag_id.to_string l.id))
        (Ids.Plant_tag_id.to_string
           (Ids.Plant_tag_id.of_key ~plant:l.plant_id ~tag:l.tag_id))
        (Ids.Plant_tag_id.to_string l.id);
      Alcotest.(check bool)
        "the link is live" true
        (Option.is_none l.deleted_at);
      Alcotest.(check bool)
        "its plant is a seed plant" true
        (List.exists
           (fun (p : Plant.t) -> Ids.Plant_id.equal p.id l.plant_id)
           Dev_seed.plants);
      Alcotest.(check bool)
        "its tag is a seed tag" true
        (List.exists
           (fun (t : Tag.t) -> Ids.Tag_id.equal t.id l.tag_id)
           Dev_seed.tags))
    links;
  Alcotest.(check int)
    "each pair appears once" (List.length links)
    (distinct_count
       (List.map
          (fun (l : Tag.Plant_tag.t) ->
            Ids.Plant_id.to_string l.plant_id
            ^ "/"
            ^ Ids.Tag_id.to_string l.tag_id)
          links))

let seed_observations () =
  let os = Dev_seed.observations in
  let count p = List.length (List.filter p os) in
  Alcotest.(check bool) "at least 15 observations" true (List.length os >= 15);
  Alcotest.(check bool)
    "every observation is live" true
    (List.for_all (fun (o : Observation.t) -> Option.is_none o.deleted_at) os);
  let date (o : Observation.t) =
    let y, m, d = Ptime.to_date o.at in
    Printf.sprintf "%04d-%02d-%02d" y m d
  in
  let month (o : Observation.t) =
    let y, m, _ = Ptime.to_date o.at in
    Printf.sprintf "%04d-%02d" y m
  in
  Alcotest.(check bool)
    "at least 3 distinct days" true
    (distinct_count (List.map date os) >= 3);
  Alcotest.(check bool)
    "at least 2 distinct months" true
    (distinct_count (List.map month os) >= 2);
  Alcotest.(check bool)
    "one has no plant" true
    (count (fun (o : Observation.t) -> Option.is_none o.plant_id) >= 1);
  Alcotest.(check bool)
    "one has no position" true
    (count (fun (o : Observation.t) -> Option.is_none o.position) >= 1);
  Alcotest.(check bool)
    "two have a place_label" true
    (count (fun (o : Observation.t) -> Option.is_some o.place_label) >= 2);
  Alcotest.(check bool)
    "one has a place_derived" true
    (count (fun (o : Observation.t) -> Option.is_some o.place_derived) >= 1);
  List.iter
    (fun (o : Observation.t) ->
      let what = Ids.Observation_id.to_string o.id in
      (match o.position with
      | None -> ()
      | Some p ->
          Alcotest.(check bool)
            (what ^ ": lat in [-90, 90]")
            true
            (p.lat >= -90. && p.lat <= 90.);
          Alcotest.(check bool)
            (what ^ ": lon in [-180, 180]")
            true
            (p.lon >= -180. && p.lon <= 180.);
          Alcotest.(check bool)
            (what ^ ": accuracy_m >= 0 or None")
            true
            (match p.accuracy_m with None -> true | Some a -> a >= 0.));
      match o.plant_id with
      | None -> ()
      | Some id ->
          Alcotest.(check bool)
            (what ^ ": its plant is a seed plant")
            true
            (List.exists
               (fun (p : Plant.t) -> Ids.Plant_id.equal p.id id)
               Dev_seed.plants))
    os

let seed_timestamps () =
  let ordered what created updated =
    Alcotest.(check bool)
      (what ^ ": updated_at >= created_at")
      true
      (Ptime.compare updated created >= 0)
  in
  List.iter
    (fun (p : Plant.t) -> ordered p.display_name p.created_at p.updated_at)
    Dev_seed.plants;
  List.iter
    (fun (t : Tag.t) -> ordered t.name t.created_at t.updated_at)
    Dev_seed.tags;
  List.iter
    (fun (l : Tag.Plant_tag.t) ->
      ordered (Ids.Plant_tag_id.to_string l.id) l.created_at l.updated_at)
    Dev_seed.plant_tags;
  List.iter
    (fun (o : Observation.t) ->
      ordered (Ids.Observation_id.to_string o.id) o.created_at o.updated_at)
    Dev_seed.observations

let seed_statements_count () =
  Alcotest.(check int)
    "one statement per seed record"
    (List.length Dev_seed.plants
    + List.length Dev_seed.tags
    + List.length Dev_seed.plant_tags
    + List.length Dev_seed.observations)
    (List.length Dev_seed.statements)

let live_counts db =
  List.map
    (fun table ->
      ( table,
        Cli.count db
          (Printf.sprintf
             "select count(*) as n from %s where deleted_at is null;\n" table)
      ))
    ["plants"; "tags"; "plant_tags"; "observations"; "photos"]

let seed_applies () =
  let db = Cli.migrated_db () in
  writes "seed" db Dev_seed.statements;
  let expected =
    [
      ("plants", 12);
      ("tags", List.length Dev_seed.tags);
      ("plant_tags", List.length Dev_seed.plant_tags);
      ("observations", List.length Dev_seed.observations);
      ("photos", 0);
    ]
  in
  Alcotest.(check (list (pair string int)))
    "the seed gives its live counts and no photo" expected (live_counts db);
  writes "seed again" db Dev_seed.statements;
  Alcotest.(check (list (pair string int)))
    "applying the seed twice gives the same counts" expected (live_counts db);
  Alcotest.(check int)
    "the seed writes no outbox entry" 0
    (Cli.count db "select count(*) as n from outbox;\n");
  Alcotest.(check (list plant_t))
    "the seed plants read back in list order"
    (List.sort
       (fun (a : Plant.t) (b : Plant.t) ->
         match
           String.compare
             (String.lowercase_ascii a.display_name)
             (String.lowercase_ascii b.display_name)
         with
         | 0 -> Ids.Plant_id.compare a.id b.id
         | c -> c)
       Dev_seed.plants)
    (all db Plants.list);
  (* Sorted by id on both sides: the comparison is of rows, not of order. *)
  let by_id to_string l =
    List.sort (fun a b -> String.compare (to_string a) (to_string b)) l
  in
  let tag_id (t : Tag.t) = Ids.Tag_id.to_string t.id in
  let obs_id (o : Observation.t) = Ids.Observation_id.to_string o.id in
  Alcotest.(check (list tag_t))
    "after the second apply the tags are the seed's"
    (by_id tag_id Dev_seed.tags)
    (by_id tag_id (all db Tags.list));
  Alcotest.(check (list observation_t))
    "after the second apply the observations are the seed's"
    (by_id obs_id Dev_seed.observations)
    (by_id obs_id (all db Observations.list))

let seed_search () =
  let db = Cli.migrated_db () in
  writes "seed" db Dev_seed.statements;
  let found = search db "digitale" in
  List.iter
    (fun name ->
      Alcotest.(check bool)
        (Printf.sprintf "\"digitale\" finds %s in the seed" name)
        true (List.mem name found))
    ["Digitale pourpre"; "Digitalis"]

(* ---------- runner ---------- *)

let () =
  let case name f = Alcotest.test_case name `Quick f in
  Alcotest.run "store queries"
    [
      ( "Stmt",
        [
          case "stmt gives back the sql and parameters of a query"
            stmt_gives_back;
          case "decode runs the query's row spec on a row object" stmt_decode;
          case "decode parses the ~json columns" stmt_decode_json;
        ] );
      ( "Plants",
        [
          case "Plants.row keeps string aliases and degrades the rest to []"
            plants_row_aliases;
          case "Plants.row ignores extra columns" plants_row_extra_keys;
          case "a plant whose aliases are not JSON text still lists"
            plants_unparsable_aliases;
          case "upsert then get round-trips every field" plants_round_trip;
          case "get ignores soft-deleted and absent plants"
            plants_round_trip_deleted;
          case "list is live plants by display_name nocase then id"
            plants_list_order;
          case "list of an empty table is empty" plants_list_empty;
          case "upsert of an existing id updates in place, children survive"
            plants_upsert_in_place;
          case "upsert with deleted_at = None revives a plant"
            plants_upsert_revives;
          case "soft_delete gives 1 then 0 and leaves children live"
            plants_soft_delete;
          case "with_tag is live plants with a live link to a live tag"
            plants_with_tag;
          case "Tags.links is live links of live tags and plants" tags_links;
          case "upsert over an existing id rewrites every column"
            plants_upsert_overwrites;
          case "upsert is insert on conflict, never replace" plants_upsert_sql;
        ] );
      ( "Observations",
        [
          case "upsert then get round-trips every field and position"
            observations_round_trip;
          case "position None writes lat, lon and accuracy_m as null"
            observations_no_position_nulls;
          case "row gives a position only when lat and lon are both set"
            observations_row_position;
          case "a record violating the table's checks fails to write"
            observations_invalid;
          case "list is live observations, at then id descending"
            observations_list_order;
          case
            "of_plant gives a deleted plant's live observations, newest first"
            observations_of_plant;
          case "unidentified gives the live observations without a plant"
            observations_unidentified;
          case "between includes from, excludes until" observations_between;
          case "soft_delete gives 1 then 0" observations_soft_delete;
          case "upsert over an existing id rewrites every column"
            observations_upsert_overwrites;
          case "upsert is insert on conflict, never replace"
            observations_upsert_sql;
        ] );
      ( "Tags",
        [
          case "upsert then get round-trips; get ignores deleted tags"
            tags_round_trip;
          case "list is live tags by name nocase then id" tags_list_order;
          case "tag inserts the of_key row, then changes nothing on a live link"
            tags_tag_inserts;
          case "untag soft-deletes, tag revives keeping id and created_at"
            tags_untag_and_revive;
          case "untag without a link changes nothing" tags_untag_absent;
          case "tag with an unknown plant or tag fails" tags_tag_unknown;
          case "upsert_plant_tag conflicts on the natural key"
            tags_upsert_plant_tag;
          case "of_plant is live tags with a live link" tags_of_plant;
          case "soft_delete gives 1 then 0" tags_soft_delete;
          case "upsert over an existing id rewrites every column"
            tags_upsert_overwrites;
          case "upsert is insert on conflict, never replace" tags_upsert_sql;
        ] );
      ( "Photos",
        [
          case "upsert then get round-trips every field" photos_round_trip;
          case "of_observation and of_plant order and filter" photos_lists;
          case "soft_delete gives 1 then 0" photos_soft_delete;
          case "upsert over an existing id rewrites every column"
            photos_upsert_overwrites;
        ] );
      ( "Settings",
        [
          case "key names are storage_target and wifi_only" settings_names;
          case "a key never set is None" settings_absent;
          case "Wifi_only round-trips as true and false" settings_wifi_only;
          case "Storage_target round-trips as its enum label"
            settings_storage_target;
          case "an unparsable stored value is Row WrongType" settings_bad_value;
        ] );
      ( "Search.match_expression",
        [
          case "folds, strips one ending, quotes and prefixes each term"
            match_expression;
        ] );
      ( "Search",
        [
          case "\"digitale\" finds Digitale pourpre and Digitalis" search_done;
          case "blank or punctuation-only text gives no query" search_blank;
          case "aliases, scientific names and folded names are searched"
            search_fields;
          case "FTS5 keywords and syntax are plain text" search_keywords;
          case "results come in Plants.list order" search_order;
          case "the index follows soft deletes, revives, renames, hard deletes"
            search_soft_delete_and_rename;
          case "the index follows tagging, renaming and deleting tags"
            search_tags;
          case "the index follows observation places" search_places;
          case "a plant matching several fields is returned once" search_once;
          case "migration 2 backfills plants present at version 1"
            search_backfill;
        ] );
      ( "Dev_seed",
        [
          case "plant, tag and observation ids start with 5eed" seed_ids_prefix;
          case "12 live plants with Digitale pourpre and Digitalis" seed_plants;
          case "at least 4 live tags with distinct names" seed_tags;
          case "plant tags use of_key ids, once per pair" seed_plant_tags;
          case "observations cover the planned cases" seed_observations;
          case "timestamps are ordered" seed_timestamps;
          case "statements has one upsert per record" seed_statements_count;
          case "applying the seed twice gives the same rows" seed_applies;
          case "\"digitale\" finds both names in the seed" seed_search;
        ] );
    ]
