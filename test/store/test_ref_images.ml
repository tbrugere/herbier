(* Native checks of app/store/ref_images.ml (the device-only [ref_images]
   table, migration 3) through the sqlite3 CLI, exactly as test_references.ml
   checks References: Cli.write_ok runs each statement as [Db.write] does on
   the device (no transaction, no outbox entry: [ref_images] is not synced).
   The Capacitor plugin itself is a device check (#dev/store). *)

module Value = Herbier_test_support.Value
module Outbox = Herbier_store.Outbox
module Plants = Herbier_store.Plants
module Ref_images = Herbier_store.Ref_images
module Ids = Herbier_domain.Ids
module Plant = Herbier_domain.Plant
module Reference = Herbier_domain.Reference
module Source = Herbier_domain.Reference.Source
module Organ = Herbier_domain.Reference.Organ
module Image = Herbier_domain.Reference.Image
module Cli = Sqlite_cli
module Text = Herbier_test_support.Text

(* ---------- fixtures ---------- *)

let time = Value.time
let t1 = time "2026-10-28T12:00:00Z"
let uuid = Value.uuid4
let id_of what of_string n = Value.id what of_string (uuid n)
let plant_id = id_of "plant id" Ids.Plant_id.of_string

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

let seed_plant db p =
  let (_ : int) =
    Cli.write_ok "seed plant" db
      (Outbox.bare_stmt (Outbox.without_entry (Plants.upsert p)))
  in
  ()

let image ?(plant_id = plant_id 0x1) ?(source = Source.Plantnet) ~organ
    ~remote_url ?(licence = "cc-by-sa") ?(attribution = "Someone")
    ?(thumb_path = None) () : Image.t =
  {plant_id; source; organ; remote_url; licence; attribution; thumb_path}

(* ---------- testables ---------- *)

let image_json (i : Image.t) =
  `Assoc
    [
      ("plant_id", `String (Ids.Plant_id.to_string i.plant_id));
      ("source", `String (Source.to_string i.source));
      ("organ", `String (Organ.to_string i.organ));
      ("remote_url", `String i.remote_url);
      ("licence", `String i.licence);
      ("attribution", `String i.attribution);
      ( "thumb_path",
        match i.thumb_path with None -> `Null | Some p -> `String p );
    ]

let images_json l = `List (List.map image_json l)

let check_images what expected actual =
  Alcotest.(check Cli.yojson) what (images_json expected) (images_json actual)

(* ---------- schema ---------- *)

let schema () =
  let db = Cli.migrated_db () in
  Alcotest.(check (list string))
    "ref_images columns"
    (List.sort String.compare
       [
         "plant_id";
         "source";
         "organ";
         "remote_url";
         "licence";
         "attribution";
         "thumb_path";
       ])
    (Cli.column_names db "ref_images");
  let info = Cli.rows db "pragma table_info(ref_images);\n" in
  let pk_cols =
    info
    |> List.filter (fun row -> Cli.int_field "pk" row > 0)
    |> List.sort (fun a b ->
        compare (Cli.int_field "pk" a) (Cli.int_field "pk" b))
    |> List.map (Cli.string_field "name")
  in
  Alcotest.(check (list string))
    "primary key is (plant_id, source, organ)"
    ["plant_id"; "source"; "organ"]
    pk_cols;
  Alcotest.(check (list string))
    "reference_organs holds exactly Organ.all's labels"
    (List.sort String.compare (List.map Organ.to_string Organ.all))
    (List.map (Cli.string_field "value")
       (Cli.rows db "select value from reference_organs order by value;\n"))

(* ---------- put, of_plant ---------- *)

let put_and_round_trip () =
  let db = Cli.migrated_db () in
  seed_plant db (plant 0x1 "Digitale");
  let with_thumb =
    image ~organ:Organ.Flower ~remote_url:"https://bs.plantnet.org/image/o/a"
      ~attribution:"Indrė Ruškytė" ~thumb_path:(Some "refthumbs/p/a.jpg") ()
  in
  let without_thumb =
    image ~organ:Organ.Leaf ~remote_url:"https://bs.plantnet.org/image/o/b"
      ~thumb_path:None ()
  in
  let (_ : int) = Cli.write_ok "put flower" db (Ref_images.put with_thumb) in
  let (_ : int) = Cli.write_ok "put leaf" db (Ref_images.put without_thumb) in
  check_images "round trip, both thumb_path forms, UTF-8 attribution kept"
    [with_thumb; without_thumb]
    (Cli.all db (Ref_images.of_plant (plant_id 0x1)))

let put_again_updates () =
  let db = Cli.migrated_db () in
  seed_plant db (plant 0x1 "Digitale");
  let v1 =
    image ~organ:Organ.Flower ~remote_url:"https://bs.plantnet.org/image/o/a"
      ~licence:"cc-by-sa" ~thumb_path:(Some "p1") ()
  in
  let v2 =
    image ~organ:Organ.Flower ~remote_url:"https://bs.plantnet.org/image/o/b"
      ~licence:"cc-by" ~thumb_path:None ()
  in
  let (_ : int) = Cli.write_ok "put v1" db (Ref_images.put v1) in
  let (_ : int) = Cli.write_ok "put v2 (same key)" db (Ref_images.put v2) in
  check_images "one row, the second's values" [v2]
    (Cli.all db (Ref_images.of_plant (plant_id 0x1)))

let of_plant_order_and_filters () =
  let db = Cli.migrated_db () in
  seed_plant db (plant 0x1 "Digitale");
  seed_plant db (plant 0x2 "Arnica");
  let flower =
    image ~plant_id:(plant_id 0x1) ~organ:Organ.Flower
      ~remote_url:"https://bs.plantnet.org/image/o/f" ()
  in
  let leaf =
    image ~plant_id:(plant_id 0x1) ~organ:Organ.Leaf
      ~remote_url:"https://bs.plantnet.org/image/o/l" ()
  in
  let habit =
    image ~plant_id:(plant_id 0x1) ~organ:Organ.Habit
      ~remote_url:"https://bs.plantnet.org/image/o/h" ()
  in
  let gbif_flower =
    image ~plant_id:(plant_id 0x1) ~source:Source.Gbif ~organ:Organ.Flower
      ~remote_url:"https://www.gbif.org/image/f" ()
  in
  let other_plant =
    image ~plant_id:(plant_id 0x2) ~organ:Organ.Flower
      ~remote_url:"https://bs.plantnet.org/image/o/other" ()
  in
  (* Put in an order different from Organ.all, to prove of_plant reorders. *)
  List.iter
    (fun img ->
      let (_ : int) = Cli.write_ok "seed image" db (Ref_images.put img) in
      ())
    [habit; flower; leaf; gbif_flower; other_plant];
  check_images
    "source label order (gbif before plantnet), then Organ.all order within a \
     source; another plant's row excluded"
    [gbif_flower; flower; leaf; habit]
    (Cli.all db (Ref_images.of_plant (plant_id 0x1)))

(* ---------- set_thumb ---------- *)

let set_thumb_rules () =
  let db = Cli.migrated_db () in
  seed_plant db (plant 0x1 "Digitale");
  seed_plant db (plant 0x2 "Arnica");
  let url = "https://bs.plantnet.org/image/o/a" in
  let row = image ~organ:Organ.Flower ~remote_url:url ~thumb_path:None () in
  (* Same organ and url: another plant's row, and a Gbif row. *)
  let other_plant =
    image ~plant_id:(plant_id 0x2) ~organ:Organ.Flower ~remote_url:url
      ~thumb_path:None ()
  in
  let gbif =
    image ~source:Source.Gbif ~organ:Organ.Flower ~remote_url:url
      ~thumb_path:None ()
  in
  List.iter
    (fun r -> ignore (Cli.write_ok "seed" db (Ref_images.put r) : int))
    [row; other_plant; gbif];
  Alcotest.(check int)
    "current url: 1 change" 1
    (Cli.write_ok "set_thumb, current url" db
       (Ref_images.set_thumb ~plant:(plant_id 0x1) ~source:Source.Plantnet
          ~organ:Organ.Flower ~remote_url:url ~path:"refthumbs/p/a.jpg"));
  check_images "path stored on that row only"
    [gbif; {row with thumb_path = Some "refthumbs/p/a.jpg"}]
    (Cli.all db (Ref_images.of_plant (plant_id 0x1)));
  check_images "the other plant's row untouched" [other_plant]
    (Cli.all db (Ref_images.of_plant (plant_id 0x2)));
  Alcotest.(check int)
    "stale url: 0 changes" 0
    (Cli.write_ok "set_thumb, stale url" db
       (Ref_images.set_thumb ~plant:(plant_id 0x1) ~source:Source.Plantnet
          ~organ:Organ.Flower
          ~remote_url:"https://bs.plantnet.org/image/o/other"
          ~path:"refthumbs/p/stale.jpg"));
  check_images "thumb_path unchanged"
    [gbif; {row with thumb_path = Some "refthumbs/p/a.jpg"}]
    (Cli.all db (Ref_images.of_plant (plant_id 0x1)));
  Alcotest.(check int)
    "absent key: 0 changes" 0
    (Cli.write_ok "set_thumb, absent key" db
       (Ref_images.set_thumb ~plant:(plant_id 0x1) ~source:Source.Plantnet
          ~organ:Organ.Habit ~remote_url:url ~path:"refthumbs/p/habit.jpg"))

(* ---------- remove ---------- *)

let remove_once_then_noop () =
  let db = Cli.migrated_db () in
  seed_plant db (plant 0x1 "Digitale");
  seed_plant db (plant 0x2 "Arnica");
  let url = "https://bs.plantnet.org/image/o/a" in
  let row =
    image ~organ:Organ.Flower ~remote_url:url ~thumb_path:(Some "p") ()
  in
  (* Each differs from [row] in one key column. *)
  let leaf = image ~organ:Organ.Leaf ~remote_url:url ~thumb_path:None () in
  let gbif =
    image ~source:Source.Gbif ~organ:Organ.Flower ~remote_url:url
      ~thumb_path:None ()
  in
  let other_plant =
    image ~plant_id:(plant_id 0x2) ~organ:Organ.Flower ~remote_url:url
      ~thumb_path:None ()
  in
  List.iter
    (fun r -> ignore (Cli.write_ok "seed" db (Ref_images.put r) : int))
    [row; leaf; gbif; other_plant];
  Alcotest.(check int)
    "first remove: 1 change" 1
    (Cli.write_ok "remove" db
       (Ref_images.remove ~plant:(plant_id 0x1) ~source:Source.Plantnet
          ~organ:Organ.Flower));
  Alcotest.(check int)
    "second remove: 0 changes" 0
    (Cli.write_ok "remove again" db
       (Ref_images.remove ~plant:(plant_id 0x1) ~source:Source.Plantnet
          ~organ:Organ.Flower));
  check_images "only that row went" [gbif; leaf]
    (Cli.all db (Ref_images.of_plant (plant_id 0x1)));
  check_images "the other plant's row stays" [other_plant]
    (Cli.all db (Ref_images.of_plant (plant_id 0x2)))

(* ---------- a second sync through the table ---------- *)

(* What the thumbnail sync does, minus the download: the first plan's rows
   put and their thumbnails set, then read back; a second plan over them has
   nothing to do and every organ is shown. *)
let second_sync_through_the_table () =
  let module Organ_photos = Herbier_refs.Organ_photos in
  let module Gbif = Herbier_refs.Sources.Gbif in
  let db = Cli.migrated_db () in
  seed_plant db (plant 0x1 "Digitale");
  let gbif_image organ url attribution : Gbif.Image.t =
    {
      occurrence_key = "1";
      url;
      organ = Some organ;
      organ_label = None;
      licence = "cc-by-sa";
      attribution;
      observation_url = None;
    }
  in
  let wanted =
    [
      ( Organ.Flower,
        gbif_image Organ.Flower "https://bs.plantnet.org/image/o/f" "Élise Ö" );
      ( Organ.Habit,
        gbif_image Organ.Habit "https://bs.plantnet.org/image/o/h" "laurence" );
    ]
  in
  let plant = plant_id 0x1 in
  let first = Organ_photos.plan ~plant ~wanted ~stored:[] in
  List.iter
    (fun (r : Image.t) ->
      ignore (Cli.write_ok "put" db (Ref_images.put r) : int);
      ignore
        (Cli.write_ok "set_thumb" db
           (Ref_images.set_thumb ~plant ~source:r.source ~organ:r.organ
              ~remote_url:r.remote_url
              ~path:("refthumbs/" ^ Organ.to_string r.organ ^ ".jpg"))
          : int))
    first.put;
  let stored = Cli.all db (Ref_images.of_plant plant) in
  let second = Organ_photos.plan ~plant ~wanted ~stored in
  check_images "put: []" [] second.put;
  check_images "remove: []" [] second.remove;
  Alcotest.(check (list string))
    "every organ shown, with its thumbnail"
    ["refthumbs/flower.jpg"; "refthumbs/habit.jpg"]
    (List.map snd (Organ_photos.shown ~wanted ~stored))

(* ---------- constraints ---------- *)

let unknown_organ_rejected () =
  let db = Cli.migrated_db () in
  seed_plant db (plant 0x1 "Digitale");
  match
    Cli.sqlite db
      (Printf.sprintf
         "pragma foreign_keys = on;\n\
          insert into ref_images (plant_id, source, organ, remote_url, \
          licence, attribution) values ('%s', 'plantnet', 'bark', 'https://x', \
          'cc-by-sa', 'x');\n"
         (uuid 0x1))
  with
  | Ok out ->
      Alcotest.failf "an organ outside the lookup should be rejected, got %s"
        out
  | Error e ->
      Alcotest.(check bool)
        "rejected on the foreign key" true
        (Text.contains ~sub:"FOREIGN KEY constraint failed" e)

let unknown_plant_rejected () =
  let db = Cli.migrated_db () in
  let row =
    image ~plant_id:(plant_id 0x99) ~organ:Organ.Flower
      ~remote_url:"https://bs.plantnet.org/image/o/a" ()
  in
  match
    Cli.sqlite db
      ("pragma foreign_keys = on;\n" ^ Cli.inline (Ref_images.put row))
  with
  | Ok out -> Alcotest.failf "an unknown plant should be rejected, got %s" out
  | Error e ->
      Alcotest.(check bool)
        "rejected on the foreign key" true
        (Text.contains ~sub:"FOREIGN KEY constraint failed" e)

(* ---------- not synced ---------- *)

let never_writes_outbox () =
  let db = Cli.migrated_db () in
  seed_plant db (plant 0x1 "Digitale");
  let before = Cli.outbox_count db in
  let row =
    image ~organ:Organ.Flower ~remote_url:"https://bs.plantnet.org/image/o/a" ()
  in
  let (_ : int) = Cli.write_ok "put" db (Ref_images.put row) in
  let (_ : int) =
    Cli.write_ok "set_thumb" db
      (Ref_images.set_thumb ~plant:(plant_id 0x1) ~source:Source.Plantnet
         ~organ:Organ.Flower ~remote_url:row.remote_url ~path:"p")
  in
  let (_ : int) =
    Cli.write_ok "remove" db
      (Ref_images.remove ~plant:(plant_id 0x1) ~source:Source.Plantnet
         ~organ:Organ.Flower)
  in
  Alcotest.(check int) "outbox count unchanged" before (Cli.outbox_count db)

(* ---------- clear_thumbs (« Libérer ») ---------- *)

let clear_thumbs_clears_every_thumb_path_only () =
  let db = Cli.migrated_db () in
  seed_plant db (plant 0x1 "Digitale");
  seed_plant db (plant 0x2 "Arnica");
  let with_thumb_a =
    image ~plant_id:(plant_id 0x1) ~organ:Organ.Flower
      ~remote_url:"https://bs.plantnet.org/image/o/a" ~licence:"cc-by-sa"
      ~attribution:"Someone" ~thumb_path:(Some "refthumbs/p1/flower.jpg") ()
  in
  let with_thumb_b =
    image ~plant_id:(plant_id 0x1) ~organ:Organ.Leaf
      ~remote_url:"https://bs.plantnet.org/image/o/b" ~licence:"cc-by"
      ~attribution:"Someone Else" ~thumb_path:(Some "refthumbs/p1/leaf.jpg") ()
  in
  let no_thumb =
    image ~plant_id:(plant_id 0x2) ~organ:Organ.Habit
      ~remote_url:"https://bs.plantnet.org/image/o/c" ~thumb_path:None ()
  in
  List.iter
    (fun r -> ignore (Cli.write_ok "seed" db (Ref_images.put r) : int))
    [with_thumb_a; with_thumb_b; no_thumb];
  Alcotest.(check int)
    "one change per row that had a thumbnail" 2
    (Cli.write_ok "clear_thumbs" db Ref_images.clear_thumbs);
  let cleared_a = {with_thumb_a with thumb_path = None}
  and cleared_b = {with_thumb_b with thumb_path = None} in
  check_images "plant 1: both thumb_path cleared, everything else kept"
    [cleared_a; cleared_b]
    (Cli.all db (Ref_images.of_plant (plant_id 0x1)));
  check_images "plant 2: already None, untouched" [no_thumb]
    (Cli.all db (Ref_images.of_plant (plant_id 0x2)));
  Alcotest.(check int)
    "a second clear_thumbs: 0 changes" 0
    (Cli.write_ok "clear_thumbs again" db Ref_images.clear_thumbs)

let clear_thumbs_leaves_the_rows_downloadable () =
  let module Organ_photos = Herbier_refs.Organ_photos in
  let db = Cli.migrated_db () in
  seed_plant db (plant 0x1 "Digitale");
  let flower =
    image ~organ:Organ.Flower ~remote_url:"https://bs.plantnet.org/image/o/a"
      ~thumb_path:(Some "refthumbs/p1/flower.jpg") ()
  in
  let leaf =
    image ~organ:Organ.Leaf ~remote_url:"https://bs.plantnet.org/image/o/b"
      ~thumb_path:(Some "refthumbs/p1/leaf.jpg") ()
  in
  List.iter
    (fun r -> ignore (Cli.write_ok "seed" db (Ref_images.put r) : int))
    [flower; leaf];
  let (_ : int) = Cli.write_ok "clear_thumbs" db Ref_images.clear_thumbs in
  let stored = Cli.all db (Ref_images.of_plant (plant_id 0x1)) in
  check_images "every thumb_path is now None"
    [{flower with thumb_path = None}; {leaf with thumb_path = None}]
    stored;
  Alcotest.(check int)
    "to_download lists every row of the plant" 2
    (List.length (Organ_photos.to_download stored))

(* ---------- cascade ---------- *)

let plant_delete_cascades () =
  let db = Cli.migrated_db () in
  seed_plant db (plant 0x1 "Digitale");
  let row =
    image ~organ:Organ.Flower ~remote_url:"https://bs.plantnet.org/image/o/a" ()
  in
  let (_ : int) = Cli.write_ok "seed" db (Ref_images.put row) in
  Cli.exec_ok "delete the plant" db
    (Printf.sprintf
       "pragma foreign_keys = on;\ndelete from plants where id = '%s';\n"
       (uuid 0x1));
  Alcotest.(check int)
    "the image row went with its plant" 0
    (List.length (Cli.rows db "select plant_id from ref_images;\n"))

(* ---------- run ---------- *)

let () =
  let case name f = Alcotest.test_case name `Quick f in
  Alcotest.run "store ref_images"
    [
      ("schema", [case "columns, primary key, lookup table values" schema]);
      ( "put, of_plant",
        [
          case
            "put then of_plant round-trips thumb_path None and Some, UTF-8 \
             attribution"
            put_and_round_trip;
          case "put twice on the same key: one row, the second's values"
            put_again_updates;
          case
            "of_plant orders by source then Organ.all, excludes another plant"
            of_plant_order_and_filters;
        ] );
      ( "set_thumb",
        [
          case
            "current url: 1 change, path stored; stale url: 0, unchanged; \
             absent key: 0"
            set_thumb_rules;
        ] );
      ("remove", [case "removes once, then a no-op" remove_once_then_noop]);
      ( "sync",
        [
          case "a second plan over the rows read back is a no-op"
            second_sync_through_the_table;
        ] );
      ( "constraints",
        [
          case "an organ outside the lookup is rejected on the foreign key"
            unknown_organ_rejected;
          case "an unknown plant is rejected on the foreign key"
            unknown_plant_rejected;
        ] );
      ( "not synced",
        [
          case "put, set_thumb and remove never write to the outbox"
            never_writes_outbox;
        ] );
      ( "clear_thumbs",
        [
          case
            "one change per row that had a thumbnail; other columns kept; a \
             second call is a no-op"
            clear_thumbs_clears_every_thumb_path_only;
          case "cleared rows are picked up by Organ_photos.to_download"
            clear_thumbs_leaves_the_rows_downloadable;
        ] );
      ( "cascade",
        [
          case "hard-deleting the plant row deletes its images"
            plant_delete_cascades;
        ] );
    ]
