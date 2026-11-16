(* Native checks of the pure store modules (Stmt, Plants,
   Observations, Tags, Photos, Settings, Search, Dev_seed): their statements
   run through the sqlite3 CLI on a database migrated with every
   Schema.batch, parameters inlined by position, rows decoded with
   Stmt.decode as Db.all does on the device. The Capacitor plugin itself is
   checked on the device (#dev/store, #dev/seed). *)

module Value = Herbier_test_support.Value
module Codec = Herbier_store.Codec
module Schema = Herbier_store.Schema
module Stmt = Herbier_store.Stmt
module Outbox = Herbier_store.Outbox
module Settings = Herbier_store.Settings
module Uploads = Herbier_store.Uploads
module Search = Herbier_store.Search
module Dev_seed = Herbier_store.Dev_seed
module Tables = Herbier_store.Tables
module Row = Postgrest.Row
module Ids = Herbier_domain.Ids
module Plant = Herbier_domain.Plant
module Observation = Herbier_domain.Observation
module Photo = Herbier_domain.Photo
module Tag = Herbier_domain.Tag
module Fold = Herbier_domain.Fold
module P = Tables.Plants
module Cli = Sqlite_cli
module Text = Herbier_test_support.Text

(* These checks are about the bare statements and their changes() counts, so
   each write goes through [Outbox.without_entry] (no entry), unwrapped with
   [Outbox.bare_stmt]; test_outbox checks the entries. *)
module Plants = struct
  include Herbier_store.Plants

  let upsert p = Outbox.bare_stmt (Outbox.without_entry (upsert p))

  let soft_delete id ~at =
    Outbox.bare_stmt (Outbox.without_entry (soft_delete id ~at))
end

module Observations = struct
  include Herbier_store.Observations

  let upsert o = Outbox.bare_stmt (Outbox.without_entry (upsert o))

  let soft_delete id ~at =
    Outbox.bare_stmt (Outbox.without_entry (soft_delete id ~at))

  let set_place_derived id ~lat ~lon name ~at =
    Outbox.bare_stmt
      (Outbox.without_entry (set_place_derived id ~lat ~lon name ~at))
end

module Photos = struct
  include Herbier_store.Photos

  let upsert p = Outbox.bare_stmt (Outbox.without_entry (upsert p))

  let soft_delete id ~at =
    Outbox.bare_stmt (Outbox.without_entry (soft_delete id ~at))
end

module Tags = struct
  include Herbier_store.Tags

  let upsert t = Outbox.bare_stmt (Outbox.without_entry (upsert t))

  let soft_delete id ~at =
    Outbox.bare_stmt (Outbox.without_entry (soft_delete id ~at))

  let tag ~plant ~tag:t ~at =
    Outbox.bare_stmt (Outbox.without_entry (tag ~plant ~tag:t ~at))

  let untag ~plant ~tag ~at =
    Outbox.bare_stmt (Outbox.without_entry (untag ~plant ~tag ~at))
end

(* ---------- fixtures ---------- *)

let time = Value.time
let uuid = Value.uuid4
let id_of what of_string n = Value.id what of_string (uuid n)
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

let plant_t = Alcotest.testable Plant.pp Plant.equal
let observation_t = Alcotest.testable Observation.pp Observation.equal
let photo_t = Alcotest.testable Photo.pp Photo.equal
let tag_t = Alcotest.testable Tag.pp Tag.equal
let plant_tag_t = Alcotest.testable Tag.Plant_tag.pp Tag.Plant_tag.equal

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
    (Text.contains ~sub:"insert or replace" sql);
  Alcotest.(check bool)
    (what ^ " is not replace into")
    false
    (Text.contains ~sub:"replace into" sql);
  Alcotest.(check bool)
    (what ^ " has an on conflict clause")
    true
    (Text.contains ~sub:"on conflict" sql)

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

let observations_to_geocode () =
  let db = Cli.migrated_db () in
  let positioned : Observation.position =
    {lat = 48.0625; lon = 7.0625; accuracy_m = None}
  in
  let no_derived = observation 0x31 t1 ~position:positioned in
  let blank_derived =
    observation 0x32 t2 ~position:positioned ~place_derived:"  "
  in
  let named_derived =
    observation 0x33 t3 ~position:positioned ~place_derived:"Près de Colmar"
  in
  let deleted =
    observation 0x34
      (time "2026-10-29T00:00:00Z")
      ~position:positioned
      ~deleted_at:(time "2026-10-29T00:00:00Z")
  in
  let no_position = observation 0x35 t1 in
  let with_label =
    observation 0x36
      (time "2026-10-29T06:00:00Z")
      ~position:positioned ~place_label:"Lac Blanc"
  in
  let blank_label =
    observation 0x37
      (time "2026-10-29T07:00:00Z")
      ~position:positioned ~place_label:"   "
  in
  writes "observations" db
    (List.map Observations.upsert
       [
         no_derived;
         blank_derived;
         named_derived;
         deleted;
         no_position;
         with_label;
         blank_label;
       ]);
  Alcotest.(check (list string))
    "no/blank place_derived, no/blank place_label, with a position, live; \
     newest first"
    [uuid 0x37; uuid 0x32; uuid 0x31]
    (List.map
       (fun (o : Observation.t) -> Ids.Observation_id.to_string o.id)
       (all db Observations.to_geocode))

let observations_labelled () =
  let db = Cli.migrated_db () in
  let positioned : Observation.position =
    {lat = 48.0625; lon = 7.0625; accuracy_m = None}
  in
  let live_labelled =
    observation 0x31 t1 ~position:positioned ~place_label:"Jardin"
  in
  let no_position_labelled = observation 0x32 t1 ~place_label:"Bois" in
  let deleted_labelled =
    observation 0x33 t1 ~position:positioned ~place_label:"Lac" ~deleted_at:t1
  in
  let blank_label =
    observation 0x34 t1 ~position:positioned ~place_label:"   "
  in
  let no_label = observation 0x35 t1 ~position:positioned in
  let second_live_labelled =
    observation 0x36 t2 ~position:positioned ~place_label:"  Col  "
  in
  writes "observations" db
    (List.map Observations.upsert
       [
         live_labelled;
         no_position_labelled;
         deleted_labelled;
         blank_label;
         no_label;
         second_live_labelled;
       ]);
  Alcotest.(check (list string))
    "live, positioned, non-blank place_label only (padding kept), newest first"
    [uuid 0x36; uuid 0x31]
    (List.map
       (fun (o : Observation.t) -> Ids.Observation_id.to_string o.id)
       (all db Observations.labelled))

let observations_set_place_derived () =
  let db = Cli.migrated_db () in
  let lat = 48.0625 and lon = 7.0625 in
  let o =
    observation 0x31 t1
      ~position:{lat; lon; accuracy_m = Some 5.}
      ~note:"l'eau" ~place_label:"Lac Blanc"
  in
  writes "observation" db [Observations.upsert o];
  check_changes "a matching, unnamed, live observation changes 1 row" 1 db
    (Observations.set_place_derived (observation_id 0x31) ~lat ~lon
       "Près du Lac Blanc" ~at:t2);
  Alcotest.(check (option observation_t))
    "get gives it back with the new name and updated_at, nothing else changed"
    (Some {o with place_derived = Some "Près du Lac Blanc"; updated_at = t2})
    (find db (Observations.get (observation_id 0x31)));
  check_changes "set_place_derived again (already named) changes 0 rows" 0 db
    (Observations.set_place_derived (observation_id 0x31) ~lat ~lon
       "Près d'ailleurs" ~at:t3);
  let blank =
    observation 0x34 t1
      ~position:{lat; lon; accuracy_m = None}
      ~place_derived:"  "
  in
  writes "an observation with a blank place_derived" db
    [Observations.upsert blank];
  check_changes "a blank place_derived counts as unnamed: 1 row" 1 db
    (Observations.set_place_derived (observation_id 0x34) ~lat ~lon
       "Près d'ailleurs" ~at:t2);
  let moved = observation 0x32 t1 ~position:{lat; lon; accuracy_m = None} in
  let deleted =
    observation 0x33 t1 ~position:{lat; lon; accuracy_m = None} ~deleted_at:t1
  in
  writes "a second and a deleted observation" db
    [Observations.upsert moved; Observations.upsert deleted];
  check_changes "a different lat changes 0 rows" 0 db
    (Observations.set_place_derived (observation_id 0x32) ~lat:(lat +. 1.) ~lon
       "Près d'ailleurs" ~at:t3);
  check_changes "a different lon changes 0 rows" 0 db
    (Observations.set_place_derived (observation_id 0x32) ~lat ~lon:(lon +. 1.)
       "Près d'ailleurs" ~at:t3);
  check_changes "a deleted observation changes 0 rows" 0 db
    (Observations.set_place_derived (observation_id 0x33) ~lat ~lon
       "Près d'ailleurs" ~at:t3);
  check_changes "an absent observation changes 0 rows" 0 db
    (Observations.set_place_derived (observation_id 0x99) ~lat ~lon
       "Près d'ailleurs" ~at:t3)

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
    (Outbox.bare_stmt (Tags.upsert_plant_tag fresh));
  Alcotest.(check (option plant_tag_t))
    "the new row is the record as given" (Some fresh) (link_row db);
  let other =
    link_of (plant_tag_id 0xd2) ~created_at:t2 ~updated_at:t3 ~deleted_at:t3
  in
  check_changes "upsert_plant_tag on an existing pair changes 1 row" 1 db
    (Outbox.bare_stmt (Tags.upsert_plant_tag other));
  Alcotest.(check (option plant_tag_t))
    "id and created_at kept, updated_at and deleted_at from the record"
    (Some
       (link_of (plant_tag_id 0xd1) ~created_at:t1 ~updated_at:t3 ~deleted_at:t3))
    (link_row db);
  check_not_replace "Tags.upsert_plant_tag"
    (Outbox.bare_stmt (Tags.upsert_plant_tag other))

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

(* Every (target x state x file id x deleted) combination: the health
   check's list is exactly the live, Drive-bound, non-null-file-id photos
   whose state is Uploaded or Original_missing. *)
let photos_in_drive () =
  let db = Cli.migrated_db () in
  writes "observation" db [Observations.upsert (observation 0x31 t1)];
  let targets = Photo.Original_target.[Drive; App_only]
  and states = Photo.Upload_state.[Pending; Uploaded; Failed; Original_missing]
  and file_ids = [None; Some "FILE"]
  and deleteds = [None; Some t2] in
  let combos =
    List.concat_map
      (fun target ->
        List.concat_map
          (fun state ->
            List.concat_map
              (fun file_id ->
                List.map
                  (fun deleted_at -> (target, state, file_id, deleted_at))
                  deleteds)
              file_ids)
          states)
      targets
  in
  let rows =
    List.mapi
      (fun i (target, state, file_id, deleted_at) ->
        photo (0x40 + i) ~observation:0x31 t1 ~original_target:target
          ~upload_state:state ?drive_file_id:file_id ?deleted_at)
      combos
  in
  writes "every combination" db (List.map Photos.upsert rows);
  let included (target, state, file_id, deleted_at) =
    Photo.Original_target.equal target Drive
    && (Photo.Upload_state.equal state Uploaded
       || Photo.Upload_state.equal state Original_missing)
    && Option.is_some file_id
    && Option.is_none deleted_at
  in
  let expected =
    combos
    |> List.mapi (fun i combo -> (i, combo))
    |> List.filter_map (fun (i, combo) ->
        match included combo with
        | true -> Some (uuid (0x40 + i))
        | false -> None)
  in
  Alcotest.(check (list string))
    "exactly the live drive/(uploaded|original_missing)/non-null rows, by id"
    (List.sort String.compare expected)
    (photo_ids (all db Photos.in_drive));
  (* A live photo of a soft-deleted observation: its original is still the
     user's, so it stays in the list. *)
  writes "a photo of a soft-deleted observation" db
    [
      Observations.upsert (observation 0x32 t1);
      Photos.upsert
        (photo 0x90 ~observation:0x32 t1
           ~original_target:Photo.Original_target.Drive
           ~upload_state:Photo.Upload_state.Uploaded ~drive_file_id:"FILE");
      Observations.soft_delete (observation_id 0x32) ~at:t2;
    ];
  Alcotest.(check bool)
    "a live photo of a soft-deleted observation is included" true
    (List.mem (uuid 0x90) (photo_ids (all db Photos.in_drive)))

(* ---------- Photos.set_app_only ---------- *)

let last_payload db =
  match List.rev (Cli.outbox db) with
  | r :: _ -> Yojson.Safe.from_string (Cli.string_field "payload_json" r)
  | [] -> Alcotest.fail "the outbox is empty"

let payload_field name payload =
  match payload with
  | `Assoc fields -> Option.value (List.assoc_opt name fields) ~default:`Null
  | _ -> Alcotest.fail "payload is not an object"

let check_edit what expected db edits =
  Alcotest.(check int) what expected (Cli.edit_ok what db edits)

let photos_set_app_only () =
  let db = Cli.migrated_db () in
  writes "observation" db [Observations.upsert (observation 0x31 t1)];
  let pending =
    photo 0xb1 ~observation:0x31 t1 ~upload_state:Photo.Upload_state.Pending
  in
  let failed =
    photo 0xb2 ~observation:0x31 t1 ~upload_state:Photo.Upload_state.Failed
  in
  let uploaded =
    photo 0xb3 ~observation:0x31 t1 ~upload_state:Photo.Upload_state.Uploaded
  in
  let original_missing =
    photo 0xb4 ~observation:0x31 t1
      ~upload_state:Photo.Upload_state.Original_missing
  in
  let app_only_pending =
    photo 0xb5 ~observation:0x31 t1
      ~original_target:Photo.Original_target.App_only
      ~upload_state:Photo.Upload_state.Pending
  in
  let deleted =
    photo 0xb6 ~observation:0x31 t1 ~upload_state:Photo.Upload_state.Pending
  in
  writes "every photo" db
    (List.map Photos.upsert
       [pending; failed; uploaded; original_missing; app_only_pending; deleted]);
  writes "soft delete" db [Photos.soft_delete deleted.id ~at:t2];
  List.iter
    (fun (what, (p : Photo.t)) ->
      check_edit
        (what ^ ": set_app_only appends 1 entry")
        1 db
        [Photos.set_app_only p.id ~at:t2];
      Alcotest.(check (option photo_t))
        (what ^ ": the row is now app_only, updated_at = at")
        (Some
           {
             p with
             original_target = Photo.Original_target.App_only;
             updated_at = t2;
           })
        (find db (Photos.get p.id));
      Alcotest.(check Cli.yojson)
        (what ^ ": the payload's original_target is app_only")
        (`String "app_only")
        (payload_field "original_target" (last_payload db)))
    [("a drive/pending photo", pending); ("a drive/failed photo", failed)];
  List.iter
    (fun (what, id) ->
      let before = Cli.outbox_count db in
      check_edit
        (what ^ ": set_app_only appends nothing")
        0 db
        [Photos.set_app_only id ~at:t3];
      Alcotest.(check int)
        (what ^ ": outbox count unchanged")
        before (Cli.outbox_count db))
    [
      ("a drive/uploaded photo", uploaded.id);
      ("a drive/original_missing photo", original_missing.id);
      ("an already app_only/pending photo", app_only_pending.id);
      ("a deleted photo", deleted.id);
      ("an absent photo", photo_id 0xb9);
    ]

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

let place_source_keys =
  [
    ("place_source_ign_offline", Settings.Place_source_ign_offline);
    ("place_source_ign_online", Settings.Place_source_ign_online);
    ("place_source_photon_online", Settings.Place_source_photon_online);
    ("location_notice_seen", Settings.Location_notice_seen);
  ]

let settings_place_source_names () =
  List.iter
    (fun (name, key) ->
      Alcotest.(check string) (name ^ ": name") name (Settings.name key))
    place_source_keys

let settings_place_source_round_trip () =
  List.iter
    (fun (name, key) ->
      let db = Cli.migrated_db () in
      Alcotest.(check (option bool))
        (name ^ ": never set is None")
        None
        (find db (Settings.get key));
      check_changes
        (name ^ ": set true changes 1 row")
        1 db (Settings.set key true);
      Alcotest.(check (option bool))
        (name ^ ": get is Some true")
        (Some true)
        (find db (Settings.get key));
      Alcotest.(check (option string))
        (name ^ ": true is stored as \"true\"")
        (Some "true") (stored_value db name);
      check_changes
        (name ^ ": set false changes 1 row")
        1 db (Settings.set key false);
      Alcotest.(check (option bool))
        (name ^ ": the second set replaces the value")
        (Some false)
        (find db (Settings.get key));
      Alcotest.(check (option string))
        (name ^ ": false is stored as \"false\"")
        (Some "false") (stored_value db name))
    place_source_keys

let settings_place_source_bad_value () =
  List.iter
    (fun (name, key) ->
      let db = Cli.migrated_db () in
      Cli.exec_ok
        (name ^ ": bad settings row")
        db
        (Printf.sprintf
           "insert into settings (key, value) values ('%s', 'yes');\n" name);
      Alcotest.(check (result (option bool) Cli.codec_error))
        (name ^ " holding \"yes\" is Row WrongType")
        (Error (Row `WrongType))
        (Cli.find_result db (Settings.get key)))
    place_source_keys

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

let timestamp_keys =
  [
    ("drive_health_checked_at", Settings.Drive_health_checked_at);
    ("last_upload_at", Settings.Last_upload_at);
  ]

let settings_timestamp_names () =
  List.iter
    (fun (name, key) ->
      Alcotest.(check string) (name ^ ": name") name (Settings.name key))
    timestamp_keys

let settings_timestamp_round_trip () =
  List.iter
    (fun (name, key) ->
      let db = Cli.migrated_db () in
      Alcotest.(check (option Cli.ptime))
        (name ^ ": never set is None")
        None
        (find db (Settings.get key));
      let t = time "2026-11-12T10:00:00.123456Z" in
      check_changes (name ^ ": set changes 1 row") 1 db (Settings.set key t);
      Alcotest.(check (option Cli.ptime))
        (name ^ ": get round-trips a Ptime.t with microseconds")
        (Some t)
        (find db (Settings.get key));
      Alcotest.(check (option string))
        (name ^ ": stored as Codec.timestamp")
        (stamp t) (stored_value db name))
    timestamp_keys

let settings_timestamp_bad_value () =
  List.iter
    (fun (name, key) ->
      let db = Cli.migrated_db () in
      Cli.exec_ok
        (name ^ ": bad settings row")
        db
        (Printf.sprintf
           "insert into settings (key, value) values ('%s', 'yesterday');\n"
           name);
      Alcotest.(check (result (option Cli.ptime) Cli.codec_error))
        (name ^ " holding \"yesterday\" is Row WrongType")
        (Error (Row `WrongType))
        (Cli.find_result db (Settings.get key)))
    timestamp_keys

let photo_id_t = Alcotest.testable Ids.Photo_id.pp Ids.Photo_id.equal

let settings_cursor () =
  let db = Cli.migrated_db () in
  let key = Settings.Drive_health_cursor in
  Alcotest.(check string)
    "named drive_health_cursor" "drive_health_cursor" (Settings.name key);
  Alcotest.(check (option photo_id_t))
    "never set is None" None
    (find db (Settings.get key));
  let id = photo_id 0x42 in
  check_changes "set changes 1 row" 1 db (Settings.set key id);
  Alcotest.(check (option photo_id_t))
    "get gives the id back" (Some id)
    (find db (Settings.get key));
  Alcotest.(check (option string))
    "stored as the id's text"
    (Some (Ids.Photo_id.to_string id))
    (stored_value db "drive_health_cursor");
  check_changes "unset changes 1 row" 1 db (Settings.unset key);
  Alcotest.(check (option photo_id_t))
    "unset: None again" None
    (find db (Settings.get key));
  check_changes "unset again changes nothing" 0 db (Settings.unset key);
  Cli.exec_ok "bad cursor row" db
    "insert into settings (key, value) values ('drive_health_cursor', 'nope');\n";
  Alcotest.(check (result (option photo_id_t) Cli.codec_error))
    "a non-uuid value is Row WrongType" (Error (Row `WrongType))
    (Cli.find_result db (Settings.get key))

let settings_root_folder () =
  let db = Cli.migrated_db () in
  let key = Settings.Drive_root_folder in
  Alcotest.(check string)
    "named drive_root_folder" "drive_root_folder" (Settings.name key);
  Alcotest.(check (option string))
    "never set is None" None
    (find db (Settings.get key));
  check_changes "set changes 1 row" 1 db (Settings.set key "1AbC_d-9");
  Alcotest.(check (option string))
    "get gives the id back" (Some "1AbC_d-9")
    (find db (Settings.get key));
  Alcotest.(check (option string))
    "stored as the id's text" (Some "1AbC_d-9")
    (stored_value db "drive_root_folder");
  check_changes "unset changes 1 row" 1 db (Settings.unset key);
  Alcotest.(check (option string))
    "unset: None again" None
    (find db (Settings.get key));
  check_changes "unset again changes nothing" 0 db (Settings.unset key);
  Cli.exec_ok "blank root folder row" db
    "insert into settings (key, value) values ('drive_root_folder', '   ');\n";
  Alcotest.(check (result (option string) Cli.codec_error))
    "a blank value is Row WrongType" (Error (Row `WrongType))
    (Cli.find_result db (Settings.get key));
  Cli.exec_ok "untrimmed root folder row" db
    "update settings set value = ' F1 ' where key = 'drive_root_folder';\n";
  Alcotest.(check (option string))
    "an untrimmed value is trimmed on read" (Some "F1")
    (find db (Settings.get key))

let drive_folder_t =
  Alcotest.testable
    (fun ppf (f : Settings.drive_folder) ->
      Format.fprintf ppf "{id = %S; name = %S}" f.id f.name)
    Settings.equal_drive_folder

let settings_drive_root_folder_picked () =
  let db = Cli.migrated_db () in
  let key = Settings.Drive_root_folder_picked in
  Alcotest.(check string)
    "named drive_root_folder_picked" "drive_root_folder_picked"
    (Settings.name key);
  Alcotest.(check (option drive_folder_t))
    "never set is None" None
    (find db (Settings.get key));
  let value : Settings.drive_folder =
    {id = "F1"; name = "Herbe d'or \xc2\xab x \xc2\xbb"}
  in
  check_changes "set changes 1 row" 1 db (Settings.set key value);
  Alcotest.(check (option drive_folder_t))
    "get gives the value back" (Some value)
    (find db (Settings.get key));
  Alcotest.(check (option string))
    "stored as compact JSON, id then name"
    (Some (Printf.sprintf {|{"id":"F1","name":"%s"}|} value.name))
    (stored_value db "drive_root_folder_picked");
  check_changes "unset changes 1 row" 1 db (Settings.unset key);
  Alcotest.(check (option drive_folder_t))
    "unset: None again" None
    (find db (Settings.get key));
  check_changes "unset again changes nothing" 0 db (Settings.unset key);
  Cli.exec_ok "not JSON" db
    "insert into settings (key, value) values ('drive_root_folder_picked', \
     'nope');\n";
  Alcotest.(check (result (option drive_folder_t) Cli.codec_error))
    "a stored value that is not JSON is Row WrongType" (Error (Row `WrongType))
    (Cli.find_result db (Settings.get key));
  Cli.exec_ok "blank id" db
    "update settings set value = '{\"id\":\" \",\"name\":\"x\"}' where key = \
     'drive_root_folder_picked';\n";
  Alcotest.(check (result (option drive_folder_t) Cli.codec_error))
    "a blank id is Row WrongType" (Error (Row `WrongType))
    (Cli.find_result db (Settings.get key));
  Cli.exec_ok "no name" db
    "update settings set value = '{\"id\":\"F1\"}' where key = \
     'drive_root_folder_picked';\n";
  Alcotest.(check (result (option drive_folder_t) Cli.codec_error))
    "a missing name is Row WrongType" (Error (Row `WrongType))
    (Cli.find_result db (Settings.get key));
  Cli.exec_ok "padded id" db
    "update settings set value = '{\"id\":\" F1 \",\"name\":\"x\"}' where key \
     = 'drive_root_folder_picked';\n";
  Alcotest.(check (option drive_folder_t))
    "an untrimmed id is trimmed on read"
    (Some {Settings.id = "F1"; name = "x"})
    (find db (Settings.get key));
  let quoted : Settings.drive_folder = {id = "F2"; name = {|a "b" \ c|}} in
  check_changes "set a name with a quote and a backslash" 1 db
    (Settings.set key quoted);
  Alcotest.(check (option string))
    "stored escaped" (Some {|{"id":"F2","name":"a \"b\" \\ c"}|})
    (stored_value db "drive_root_folder_picked");
  Alcotest.(check (option drive_folder_t))
    "a quote and a backslash round-trip" (Some quoted)
    (find db (Settings.get key))

let settings_drive_root_folder_default () =
  let db = Cli.migrated_db () in
  let key = Settings.Drive_root_folder_default in
  Alcotest.(check string)
    "named drive_root_folder_default" "drive_root_folder_default"
    (Settings.name key);
  Alcotest.(check (option string))
    "never set is None" None
    (find db (Settings.get key));
  check_changes "set changes 1 row" 1 db (Settings.set key "H1");
  Alcotest.(check (option string))
    "get gives the id back" (Some "H1")
    (find db (Settings.get key));
  Alcotest.(check (option string))
    "stored as the id's text" (Some "H1")
    (stored_value db "drive_root_folder_default");
  check_changes "unset changes 1 row" 1 db (Settings.unset key);
  Cli.exec_ok "blank default row" db
    "insert into settings (key, value) values ('drive_root_folder_default', ' \
     ');\n";
  Alcotest.(check (result (option string) Cli.codec_error))
    "a blank value is Row WrongType" (Error (Row `WrongType))
    (Cli.find_result db (Settings.get key))

(* Settings.Drive_account (4m « Dossier Drive »): the email of the Google
   account Drive tokens are asked for, trimmed on read, local only. *)
let settings_drive_account () =
  let db = Cli.migrated_db () in
  let key = Settings.Drive_account in
  Alcotest.(check string)
    "named drive_account" "drive_account" (Settings.name key);
  Alcotest.(check (option string))
    "never set is None" None
    (find db (Settings.get key));
  check_changes "set changes 1 row" 1 db (Settings.set key "a@x.fr");
  Alcotest.(check (option string))
    "get gives the email back" (Some "a@x.fr")
    (find db (Settings.get key));
  Alcotest.(check (option string))
    "stored as the email's text" (Some "a@x.fr")
    (stored_value db "drive_account");
  Cli.exec_ok "untrimmed account row" db
    "update settings set value = ' a@x.fr ' where key = 'drive_account';\n";
  Alcotest.(check (option string))
    "an untrimmed value is trimmed on read" (Some "a@x.fr")
    (find db (Settings.get key));
  Cli.exec_ok "blank account row" db
    "update settings set value = '   ' where key = 'drive_account';\n";
  Alcotest.(check (result (option string) Cli.codec_error))
    "a blank value is Row WrongType" (Error (Row `WrongType))
    (Cli.find_result db (Settings.get key))

(* A switch of Drive account runs Settings.drive_choice's statements in one
   transaction (as Drive_root.write does): the account is set, the old
   account's three root-folder keys are forgotten, and nothing else changes:
   not the other settings, not the device-only [uploads] table, whose waiting
   rows the queue keeps across the switch. *)
let settings_drive_account_transaction_leaves_other_rows_alone () =
  let db = Cli.migrated_db () in
  (* unrelated settings, as if set well before the account was ever chosen. *)
  check_changes "seed Storage_target" 1 db
    (Settings.set Settings.Storage_target Photo.Original_target.Drive);
  check_changes "seed Wifi_only" 1 db (Settings.set Settings.Wifi_only true);
  let cursor = photo_id 0x42 in
  check_changes "seed Drive_health_cursor" 1 db
    (Settings.set Settings.Drive_health_cursor cursor);
  let uploaded_at = time "2026-10-01T00:00:00Z" in
  check_changes "seed Last_upload_at" 1 db
    (Settings.set Settings.Last_upload_at uploaded_at);
  (* the previous account's folders, which the switch below forgets. *)
  check_changes "seed the previous account's root folder" 1 db
    (Settings.set Settings.Drive_root_folder "OLD1");
  check_changes "seed the previous account's picked folder" 1 db
    (Settings.set Settings.Drive_root_folder_picked
       {Settings.id = "OLD1"; name = "Ancien"});
  check_changes "seed the previous account's default folder" 1 db
    (Settings.set Settings.Drive_root_folder_default "H0");
  (* an observation, one of its photos, and an upload row with a session in
     progress: the row the queue keeps waiting across the switch. *)
  let (_ : int) =
    write "seed observation" db (Observations.upsert (observation 0x31 t0))
  in
  let (_ : int) =
    write "seed photo" db (Photos.upsert (photo ~observation:0x31 0x51 t0))
  in
  let uploading_id = photo_id 0x51 in
  let upload_row : Uploads.t =
    {
      photo_id = uploading_id;
      path = "originals/x";
      mime = "image/jpeg";
      size_bytes = 12_345;
      session =
        Some {Uploads.url = "https://example.test/session"; created_at = t0};
      attempts = 0;
      last_error = None;
      created_at = t0;
    }
  in
  let (_ : int) = write "seed upload row" db (Uploads.put upload_row) in
  let upload_row_json db =
    match
      Cli.rows db
        (Printf.sprintf "select * from uploads where photo_id = '%s';\n"
           (Ids.Photo_id.to_string uploading_id))
    with
    | [row] -> row
    | rows ->
        Alcotest.failf "uploads: %d rows for the photo, expected one"
          (List.length rows)
  in
  let before = upload_row_json db in
  let module Drive = Herbier_photos.Drive in
  let ({account; ids} : Drive.account_choice) =
    Drive.choose_for_account
      {Drive.root = Some "OLD1"; picked = Some "OLD1"; default = Some "H0"}
      ~stored:(Some "old@x.fr") ~account:"new@x.fr" ~folder:None
  in
  let switch_stmts =
    Settings.drive_choice ~account ~at:t0 ~root:ids.root ~picked:None
      ~default:ids.default
  in
  Cli.exec_ok "drive account switch, one transaction" db
    ("begin;\n"
    ^ String.concat "" (List.map Cli.inline switch_stmts)
    ^ "commit;\n");
  Alcotest.(check (option string))
    "Drive_account is now set" (Some "new@x.fr")
    (find db (Settings.get Settings.Drive_account));
  Alcotest.(check (option Cli.ptime))
    "the time of the change is stored" (Some t0)
    (find db (Settings.get Settings.Drive_account_changed_at));
  Alcotest.(check (option string))
    "the previous account's root folder is forgotten" None
    (find db (Settings.get Settings.Drive_root_folder));
  Alcotest.(check (option string))
    "the previous account's picked folder is forgotten" None
    (Option.map
       (fun (f : Settings.drive_folder) -> f.id)
       (find db (Settings.get Settings.Drive_root_folder_picked)));
  Alcotest.(check (option string))
    "the previous account's default folder is forgotten" None
    (find db (Settings.get Settings.Drive_root_folder_default));
  Alcotest.(check (option string))
    "Storage_target untouched" (Some "drive")
    (stored_value db "storage_target");
  Alcotest.(check (option bool))
    "Wifi_only untouched" (Some true)
    (find db (Settings.get Settings.Wifi_only));
  Alcotest.(check (option photo_id_t))
    "Drive_health_cursor untouched" (Some cursor)
    (find db (Settings.get Settings.Drive_health_cursor));
  Alcotest.(check (option Cli.ptime))
    "Last_upload_at untouched" (Some uploaded_at)
    (find db (Settings.get Settings.Last_upload_at));
  Alcotest.check Cli.yojson
    "the upload row (with its session) is identical: the queue keeps waiting \
     rows across an account change"
    before (upload_row_json db)

let settings_unset_keeps_others () =
  let db = Cli.migrated_db () in
  check_changes "set Wifi_only" 1 db (Settings.set Settings.Wifi_only true);
  check_changes "unset an unset key changes nothing" 0 db
    (Settings.unset Settings.Drive_health_cursor);
  Alcotest.(check (option bool))
    "Wifi_only kept" (Some true)
    (find db (Settings.get Settings.Wifi_only))

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

(* ---------- Fold.matches and Search.match_expression ---------- *)

(* A query with no term ([match_expression] is [None]) matches no text. *)
let matches_false_when_no_term () =
  let no_term =
    [""; "  , "; "\xf0\x9f\x8c\xbf"; "\xc2\xab"; "\xe2\x80\x94"; "-'\"*"]
  and texts =
    [
      "";
      "Jardin";
      "Col de la Schlucht";
      "\xc2\xab Le Pr\xc3\xa9 \xc2\xbb";
      "-'\"*";
    ]
  in
  List.iter
    (fun query ->
      Alcotest.(check bool)
        (Printf.sprintf "match_expression %S is None" query)
        true
        (Option.is_none (Search.match_expression query));
      List.iter
        (fun text ->
          Alcotest.(check bool)
            (Printf.sprintf "matches ~query:%S %S" query text)
            false (Fold.matches ~query text))
        texts)
    no_term

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

let search_by_name () =
  let db = three_plants_db () in
  writes "observations" db
    [
      Observations.upsert
        (observation 0x35 t1 ~plant:0xd3 ~place_label:"Col de la Schlucht");
    ];
  let by_name text =
    match Search.plants_by_name text with
    | None -> Alcotest.failf "Search.plants_by_name %S is None" text
    | Some q -> names (all db q)
  in
  Alcotest.(check (list string))
    "a place_label does not find the plant" [] (by_name "schlucht");
  Alcotest.(check (list string))
    "names still match" ["Églantier"] (by_name "rosa");
  Alcotest.(check (list string))
    "two terms in the names" ["Digitale pourpre"]
    (by_name "digitale pourpre");
  Alcotest.(check bool)
    "blank is None" true
    (Option.is_none (Search.plants_by_name "  "))

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
let has_any_of chars s = List.exists (fun c -> Text.contains ~sub:c s) chars
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
  Cli.write_all_bare_ok "seed" db Dev_seed.statements;
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
  Cli.write_all_bare_ok "seed again" db Dev_seed.statements;
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
  Cli.write_all_bare_ok "seed" db Dev_seed.statements;
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
          case
            "to_geocode is live, positioned observations without a derived \
             name or a label, newest first"
            observations_to_geocode;
          case
            "labelled is live, positioned observations with a non-blank \
             place_label, newest first"
            observations_labelled;
          case
            "set_place_derived changes 1 row when live, unnamed and at the \
             given position, else 0"
            observations_set_place_derived;
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
          case
            "in_drive: exactly the live \
             drive/(uploaded|original_missing)/non-null-file-id rows, over \
             every combination"
            photos_in_drive;
          case
            "set_app_only: a drive/pending or drive/failed photo becomes \
             app_only with one outbox entry; uploaded, original_missing, \
             already app_only, deleted and absent photos are no-ops"
            photos_set_app_only;
        ] );
      ( "Settings",
        [
          case "key names are storage_target and wifi_only" settings_names;
          case "a key never set is None" settings_absent;
          case "Wifi_only round-trips as true and false" settings_wifi_only;
          case "Storage_target round-trips as its enum label"
            settings_storage_target;
          case "an unparsable stored value is Row WrongType" settings_bad_value;
          case
            "the place-source and notice keys are named \
             place_source_ign_online, place_source_photon_online, \
             location_notice_seen"
            settings_place_source_names;
          case "each place-source / notice key round-trips as true and false"
            settings_place_source_round_trip;
          case "each place-source / notice key holding \"yes\" is Row WrongType"
            settings_place_source_bad_value;
          case
            "the Drive health check and last upload keys are named \
             drive_health_checked_at and last_upload_at"
            settings_timestamp_names;
          case
            "each timestamp key round-trips a Ptime.t with microseconds, \
             stored as Codec.timestamp"
            settings_timestamp_round_trip;
          case "each timestamp key holding \"yesterday\" is Row WrongType"
            settings_timestamp_bad_value;
          case
            "the health cursor round-trips a photo id, unset deletes it, a bad \
             value is Row WrongType"
            settings_cursor;
          case "unset touches only its own key" settings_unset_keeps_others;
          case
            "the root folder key round-trips the id's text, trimmed, a blank \
             stored value is Row WrongType"
            settings_root_folder;
          case
            "the picked-folder key round-trips {id; name} as compact JSON, id \
             then name; invalid JSON, a blank id or a missing name is Row \
             WrongType"
            settings_drive_root_folder_picked;
          case
            "the default-folder key round-trips the id's text; a blank value \
             is Row WrongType"
            settings_drive_root_folder_default;
          case
            "the drive account key round-trips the email, trimmed; a blank \
             stored value is Row WrongType"
            settings_drive_account;
          case
            "a drive account switch (account set, the three root keys \
             set/unset) in one transaction leaves other settings and a waiting \
             upload row untouched"
            settings_drive_account_transaction_leaves_other_rows_alone;
        ] );
      ( "Search.match_expression",
        [
          case "folds, strips one ending, quotes and prefixes each term"
            match_expression;
        ] );
      ( "Fold.matches",
        [
          case "is false whenever match_expression has no term"
            matches_false_when_no_term;
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
          case "plants_by_name ignores observation places" search_by_name;
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
