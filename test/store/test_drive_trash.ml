(* Native checks of app/store/drive_trash.ml and migration 11's trigger
   (M8.94) through the sqlite3 CLI: every delete path of the app queues the
   Drive original of a Drive photo for the bin in its own transaction (the
   edits run through Cli.edit_ok as Db.edit runs them on the device), a move
   does not, and the statements of Drive_trash round-trip. *)

module Drive_trash = Herbier_store.Drive_trash
module Outbox = Herbier_store.Outbox
module Observations = Herbier_store.Observations
module Photos = Herbier_store.Photos
module Plants = Herbier_store.Plants
module Cascade = Herbier_store.Cascade
module Ids = Herbier_domain.Ids
module Observation = Herbier_domain.Observation
module Photo = Herbier_domain.Photo
module Plant = Herbier_domain.Plant
module Value = Herbier_test_support.Value
module Cli = Sqlite_cli

(* ---------- fixtures ---------- *)

let time = Value.time
let uuid = Value.uuid4
let id_of what of_string n = Value.id what of_string (uuid n)
let photo_id = id_of "photo id" Ids.Photo_id.of_string
let observation_id = id_of "observation id" Ids.Observation_id.of_string
let plant_id = id_of "plant id" Ids.Plant_id.of_string
let t0 = time "2026-11-12T10:00:00Z"
let t1 = time "2026-11-22T09:00:00Z"
let plant = Plant.v ~id:(plant_id 0x51) ~at:t0 "Ortie"

let observation ?plant n : Observation.t =
  {
    id = observation_id n;
    plant_id = plant;
    at = t0;
    position = None;
    place_label = None;
    place_detail = None;
    place_derived = None;
    note = None;
    created_at = t0;
    updated_at = t0;
    deleted_at = None;
  }

(* [file]: the Drive file id; [Uploaded] with one, [Pending] without. *)
let photo ?(target = Photo.Original_target.Drive) ?file ~observation:obs n :
    Photo.t =
  {
    id = photo_id n;
    observation_id = observation_id obs;
    taken_at = t0;
    width = 1024;
    height = 768;
    sha256 = String.make 64 'a';
    preview_path = Printf.sprintf "previews/%d.webp" n;
    preview_bucket_key = None;
    original_target = target;
    drive_file_id = file;
    upload_state =
      (match file with
      | Some _ -> Photo.Upload_state.Uploaded
      | None -> Photo.Upload_state.Pending);
    created_at = t0;
    updated_at = t0;
    deleted_at = None;
  }

let bare db what edit =
  let (_ : int) =
    Cli.write_ok what db (Outbox.bare_stmt (Outbox.without_entry edit))
  in
  ()

(* The plant, two of its observations (0x31, 0x32) and one without plant
   (0x33), then [photos], all bypassing the outbox as a pull would. *)
let seeded_db photos =
  let db = Cli.migrated_db () in
  bare db "seed plant" (Plants.upsert plant);
  List.iter
    (fun o -> bare db "seed observation" (Observations.upsert o))
    [
      observation ~plant:plant.id 0x31;
      observation ~plant:plant.id 0x32;
      observation 0x33;
    ];
  List.iter (fun p -> bare db "seed photo" (Photos.upsert p)) photos;
  db

let trash_pairs db =
  List.map
    (fun (r : Drive_trash.t) -> (Ids.Photo_id.to_string r.photo_id, r.file_id))
    (Cli.all db Drive_trash.all)

let pairs = Alcotest.(list (pair string string))
let pid n = Ids.Photo_id.to_string (photo_id n)
let sorted l = List.sort compare l

(* ---------- each delete path queues its Drive originals ---------- *)

(* 4h « Supprimer » and 4c's long-press: Delete_plan.observation_edits is
   Cascade.observation. *)
let observation_delete () =
  let db =
    seeded_db
      [
        photo ~file:"F1" ~observation:0x31 0x1;
        photo ~observation:0x31 0x2;
        photo ~target:App_only ~observation:0x31 0x3;
        photo ~file:"F4" ~observation:0x32 0x4;
      ]
  in
  let (_ : int) =
    Cli.edit_ok "delete observation" db
      (Cascade.observation ~at:t1
         ~photos:[photo_id 0x1; photo_id 0x2; photo_id 0x3]
         (observation_id 0x31))
  in
  Alcotest.check pairs
    "only the uploaded Drive photo of that observation; none for the one still \
     waiting, the app-only one, or another observation's"
    [(pid 0x1, "F1")]
    (trash_pairs db);
  match Cli.all db Drive_trash.all with
  | [r] ->
      Alcotest.(check int) "attempts 0" 0 r.attempts;
      Alcotest.(check (option string)) "no error" None r.last_error;
      Alcotest.(check bool)
        "created now (after the fixtures' times), decodable" true
        (Ptime.is_later r.created_at ~than:t0)
  | rows -> Alcotest.failf "expected one row, got %d" (List.length rows)

(* 5a and 4a's long-press: Delete_plan.plant_edits is Cascade.plant. *)
let plant_cascade () =
  let db =
    seeded_db
      [
        photo ~file:"F1" ~observation:0x31 0x1;
        photo ~file:"F2" ~observation:0x32 0x2;
        photo ~observation:0x32 0x3;
        photo ~file:"F9" ~observation:0x33 0x9;
      ]
  in
  let (_ : int) =
    Cli.edit_ok "delete plant" db
      (Cascade.plant ~at:t1
         ~photos:[photo_id 0x1; photo_id 0x2; photo_id 0x3]
         ~observations:[observation_id 0x31; observation_id 0x32]
         ~tags:[] plant.id)
  in
  Alcotest.check pairs
    "both observations' uploaded photos; not the unidentified one's"
    (sorted [(pid 0x1, "F1"); (pid 0x2, "F2")])
    (sorted (trash_pairs db))

(* 5e « Retirer d'Herbier »: Photos.soft_delete. *)
let viewer_delete () =
  let db =
    seeded_db
      [
        photo ~file:"F1" ~observation:0x31 0x1;
        photo ~file:"F2" ~observation:0x31 0x2;
      ]
  in
  let (_ : int) =
    Cli.edit_ok "remove photo" db [Photos.soft_delete (photo_id 0x2) ~at:t1]
  in
  Alcotest.check pairs "the removed photo only"
    [(pid 0x2, "F2")]
    (trash_pairs db)

(* 5e « Déplacer vers une autre observation »: an upsert of the photo with
   another observation; and the queue's own updates. *)
let move_and_updates_queue_nothing () =
  let p = photo ~file:"F1" ~observation:0x31 0x1 in
  let db = seeded_db [p] in
  let (_ : int) =
    Cli.edit_ok "move" db
      [
        Photos.upsert
          {p with observation_id = observation_id 0x32; updated_at = t1};
      ]
  in
  let (_ : int) =
    Cli.edit_ok "set_upload" db
      [
        Photos.set_upload p.id ~state:Original_missing
          ~drive_file_id:(Some "F1") ~at:t1;
      ]
  in
  Alcotest.check pairs "a move keeps the file: no row" [] (trash_pairs db)

let pulled_delete_and_redelete () =
  let p = photo ~file:"F1" ~observation:0x31 0x1 in
  let db = seeded_db [p] in
  bare db "pulled delete"
    (Photos.upsert {p with deleted_at = Some t1; updated_at = t1});
  Alcotest.check pairs "a delete pulled from another install queues it too"
    [(pid 0x1, "F1")]
    (trash_pairs db);
  let (_ : int) =
    Cli.write_ok "remove" db (Drive_trash.remove (photo_id 0x1))
  in
  bare db "pulled again, still deleted"
    (Photos.upsert {p with deleted_at = Some t1; updated_at = t1});
  Alcotest.check pairs "an already deleted photo written again: no new row" []
    (trash_pairs db)

let pulled_new_deleted_row_queues_nothing () =
  let db = seeded_db [] in
  bare db "first pull of a deleted photo"
    (Photos.upsert
       {(photo ~file:"F1" ~observation:0x31 0x1) with deleted_at = Some t1});
  Alcotest.check pairs "an insert is not a delete: no row" [] (trash_pairs db)

(* ---------- the statements ---------- *)

let statements () =
  let db =
    seeded_db [photo ~observation:0x31 0x1; photo ~observation:0x31 0x2]
  in
  Alcotest.(check int)
    "add: one row" 1
    (Cli.write_ok "add" db
       (Drive_trash.add (photo_id 0x1) ~file_id:"F1" ~at:t0));
  Alcotest.(check int)
    "add again: kept, nothing changed" 0
    (Cli.write_ok "add again" db
       (Drive_trash.add (photo_id 0x1) ~file_id:"OTHER" ~at:t1));
  Alcotest.check pairs "the first add's file" [(pid 0x1, "F1")] (trash_pairs db);
  let r =
    {
      Drive_trash.photo_id = photo_id 0x1;
      file_id = "F1";
      attempts = 2;
      last_error = Some "HTTP 403";
      created_at = t0;
    }
  in
  let (_ : int) = Cli.write_ok "put" db (Drive_trash.put r) in
  (match Cli.all db Drive_trash.all with
  | [got] ->
      Alcotest.(check bool) "put round-trips" true (Drive_trash.equal r got)
  | rows -> Alcotest.failf "expected one row, got %d" (List.length rows));
  (match Cli.write db (Drive_trash.add (photo_id 0x2) ~file_id:"  " ~at:t0) with
  | Error _ -> ()
  | Ok _ -> Alcotest.fail "a blank file id must be refused (check)");
  Alcotest.(check int)
    "remove: one row" 1
    (Cli.write_ok "remove" db (Drive_trash.remove (photo_id 0x1)));
  Alcotest.check pairs "empty" [] (trash_pairs db)

let () =
  Alcotest.run "drive_trash"
    [
      ( "delete paths",
        [
          Alcotest.test_case "observation delete (4h, 4c)" `Quick
            observation_delete;
          Alcotest.test_case "plant cascade (5a, 4a)" `Quick plant_cascade;
          Alcotest.test_case "viewer « Retirer » (5e)" `Quick viewer_delete;
          Alcotest.test_case "a move or an upload update: nothing" `Quick
            move_and_updates_queue_nothing;
          Alcotest.test_case "a pulled delete; a deleted row written again"
            `Quick pulled_delete_and_redelete;
          Alcotest.test_case "a deleted row pulled for the first time" `Quick
            pulled_new_deleted_row_queues_nothing;
        ] );
      ( "statements",
        [Alcotest.test_case "add, put, all, remove" `Quick statements] );
    ]
