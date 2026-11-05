module Cap_error = Herbier_bindings.Cap_error
module Cap_sqlite = Herbier_bindings.Cap_sqlite
module Db = Herbier_store.Db
module Codec = Herbier_store.Codec
module Schema = Herbier_store.Schema
module Plants = Herbier_store.Tables.Plants
module Row = Postgrest.Row
module Plant_id = Herbier_domain.Ids.Plant_id
module Photo_id = Herbier_domain.Ids.Photo_id

type failure =
  | Store of Db.error
  | Plugin of Cap_error.t
  | Mismatch of {expected : string; got : string}

let failure_to_string = function
  | Store e -> Db.error_to_string e
  | Plugin e -> Cap_error.to_string e
  | Mismatch {expected; got} ->
      Printf.sprintf "expected %S, got %S" expected got

(* Duplicated from storage_check: the dev pages share no module. *)
let append log text = Brr.El.append_children log [Brr.El.div [Brr.El.txt' text]]
let heading log text = Brr.El.append_children log [Brr.El.h2 [Brr.El.txt' text]]
let store fut = Fut.map (Result.map_error (fun e -> Store e)) fut
let plugin fut = Fut.map (Result.map_error (fun e -> Plugin e)) fut
let no_detail _ = None

let step log label ~detail fut =
  Fut.map
    (fun r ->
      (match r with
      | Ok v -> (
          match detail v with
          | None -> append log (label ^ ": ok")
          | Some d -> append log (label ^ ": ok · " ^ d))
      | Error e -> append log (label ^ ": " ^ failure_to_string e));
      r)
    fut

let expect print expected fut =
  Fut.map
    (fun r ->
      Result.bind r (fun got ->
          match got = expected with
          | true -> Ok got
          | false ->
              Error (Mismatch {expected = print expected; got = print got})))
    (store fut)

let now () =
  let p = Brr.G.performance in
  Brr.Performance.time_origin_ms p +. Brr.Performance.now_ms p
  |> Printf.sprintf "%.0f"

type master

let name_row : (master, string) Row.t =
  Row.col {ty = Not_Null Str; name = "name"}

let table_names =
  [
    "observations";
    "outbox";
    "photo_original_targets";
    "photo_upload_states";
    "photos";
    "plant_refs";
    "plant_tags";
    "plants";
    "reference";
    "reference_sources";
    "reference_statuses";
    "settings";
    "sync_state";
    "tags";
  ]

let print_names = String.concat ", "

let check_tables log db =
  step log "tables"
    ~detail:(fun names -> Some (string_of_int (List.length names)))
    (expect print_names table_names
       (Db.query db ~json:[] name_row
          "select name from sqlite_master where type = 'table' and name not \
           like 'sqlite_%' order by name"
          []))

let check_version log db =
  step log "user_version = 1" ~detail:no_detail
    (expect string_of_int 1 (Db.user_version db))

type plant = {
  id : Plant_id.t;
  display_name : string;
  aliases : Yojson.Safe.t;
  scientific_name : string option;
  authorship : string option;
  gbif_key : int option;
  notes : string;
  notes_updated_at : Ptime.t option;
  cover_photo_id : Photo_id.t option;
  created_at : Ptime.t;
  updated_at : Ptime.t;
  deleted_at : Ptime.t option;
}

let plant_row : (Plants.t, plant) Row.t =
  let open Row.Syntax in
  let+ id = Row.col Plants.id
  and+ display_name = Row.col Plants.display_name
  and+ aliases = Row.col Plants.aliases
  and+ scientific_name = Row.col Plants.scientific_name
  and+ authorship = Row.col Plants.authorship
  and+ gbif_key = Row.col Plants.gbif_key
  and+ notes = Row.col Plants.notes
  and+ notes_updated_at = Row.col Plants.notes_updated_at
  and+ cover_photo_id = Row.col Plants.cover_photo_id
  and+ created_at = Row.col Plants.created_at
  and+ updated_at = Row.col Plants.updated_at
  and+ deleted_at = Row.col Plants.deleted_at in
  {
    id;
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

let params p =
  [
    Codec.param Plants.id p.id;
    Codec.param Plants.display_name p.display_name;
    Codec.param Plants.aliases p.aliases;
    Codec.param Plants.scientific_name p.scientific_name;
    Codec.param Plants.authorship p.authorship;
    Codec.param Plants.gbif_key p.gbif_key;
    Codec.param Plants.notes p.notes;
    Codec.param Plants.notes_updated_at p.notes_updated_at;
    Codec.param Plants.cover_photo_id p.cover_photo_id;
    Codec.param Plants.created_at p.created_at;
    Codec.param Plants.updated_at p.updated_at;
    Codec.param Plants.deleted_at p.deleted_at;
  ]

(* Built from Tables, so a renamed column breaks this page at compile time. *)
let insert_plant =
  let columns =
    [
      Plants.id.name;
      Plants.display_name.name;
      Plants.aliases.name;
      Plants.scientific_name.name;
      Plants.authorship.name;
      Plants.gbif_key.name;
      Plants.notes.name;
      Plants.notes_updated_at.name;
      Plants.cover_photo_id.name;
      Plants.created_at.name;
      Plants.updated_at.name;
      Plants.deleted_at.name;
    ]
  in
  Printf.sprintf "insert into plants (%s) values (%s)"
    (String.concat ", " columns)
    (String.concat ", " (List.map (fun _ -> "?") columns))

let print_param = function
  | Codec.Null -> "null"
  | Int i -> string_of_int i
  | Float f -> Printf.sprintf "%.17g" f
  | Text s -> s

let print_plant p = String.concat " | " (List.map print_param (params p))

let plant_equal a b =
  Plant_id.equal a.id b.id
  && String.equal a.display_name b.display_name
  && Yojson.Safe.equal a.aliases b.aliases
  && Option.equal String.equal a.scientific_name b.scientific_name
  && Option.equal String.equal a.authorship b.authorship
  && Option.equal Int.equal a.gbif_key b.gbif_key
  && String.equal a.notes b.notes
  && Option.equal Ptime.equal a.notes_updated_at b.notes_updated_at
  && Option.equal Photo_id.equal a.cover_photo_id b.cover_photo_id
  && Ptime.equal a.created_at b.created_at
  && Ptime.equal a.updated_at b.updated_at
  && Option.equal Ptime.equal a.deleted_at b.deleted_at

(* Constants of this page: a parse failure is a typo here, not data. *)
let time s =
  match Ptime.of_rfc3339 s with
  | Ok (t, _, _) -> t
  | Error _ -> invalid_arg ("Store_check.time " ^ s)

let bare () =
  {
    id = Plant_id.fresh ();
    display_name = "Plante sans nom";
    aliases = `List [];
    scientific_name = None;
    authorship = None;
    gbif_key = None;
    notes = "";
    notes_updated_at = None;
    cover_photo_id = None;
    created_at = time "2026-10-28T12:00:05.000001Z";
    updated_at = time "2026-10-28T12:00:05.000001Z";
    deleted_at = None;
  }

let full () =
  {
    id = Plant_id.fresh ();
    display_name = "Digitale pourpre";
    aliases = `List [`String "Gant de Notre-Dame"; `String "Doigtier"];
    scientific_name = Some "Digitalis purpurea";
    authorship = Some "L.";
    gbif_key = Some 3172304;
    notes = "Talus ombragé, « fleurs » en juin.";
    notes_updated_at = Some (time "2026-10-28T13:14:15.123456Z");
    cover_photo_id = Some (Photo_id.fresh ());
    created_at = time "2026-10-28T13:00:00.654321Z";
    updated_at = time "2026-10-28T13:14:15.123456Z";
    deleted_at = Some (time "2026-10-28T14:00:00.5Z");
  }

let expect_changed fut =
  Fut.map
    (fun r ->
      Result.bind r (function
        | 1 -> Ok 1
        | n ->
            Error (Mismatch {expected = "1 row changed"; got = string_of_int n})))
    (store fut)

let expect_plants expected fut =
  let print rows = String.concat " / " (List.map print_plant rows) in
  Fut.map
    (fun r ->
      Result.bind r (fun got ->
          match List.equal plant_equal expected got with
          | true -> Ok got
          | false ->
              Error (Mismatch {expected = print expected; got = print got})))
    (store fut)

let round_trip log db =
  let open Fut.Result_syntax in
  let bare = bare () and full = full () in
  let* (_ : int) =
    step log "insert bare" ~detail:no_detail
      (expect_changed (Db.run db insert_plant (params bare)))
  in
  let* (_ : int) =
    step log "insert full" ~detail:no_detail
      (expect_changed (Db.run db insert_plant (params full)))
  in
  let+ (_ : plant list) =
    step log "read back = inserted"
      ~detail:(fun rows -> Some (Printf.sprintf "%d rows" (List.length rows)))
      (expect_plants [bare; full]
         (Db.query db
            ~json:[Codec.json Plants.aliases]
            plant_row "select * from plants order by created_at" []))
  in
  ()

type count

let count_row : (count, int) Row.t = Row.col {ty = Not_Null Integer; name = "n"}

let check_count log db =
  step log "2 plants rows" ~detail:no_detail
    (expect
       (fun rows -> String.concat ", " (List.map string_of_int rows))
       [2]
       (Db.query db ~json:[] count_row "select count(*) as n from plants" []))

(* Runs [f db], then closes [db] when [f] failed, keeping [f]'s error: the
   next group then starts with no connection left open. *)
let closing_on_error db f =
  let open Fut.Syntax in
  let* r = f db in
  match r with
  | Ok v -> Fut.ok v
  | Error e ->
      let+ (_ : (unit, Db.error) result) = Db.close db in
      Error e

let fresh log database =
  let open Fut.Result_syntax in
  let* db =
    step log "open (no file)" ~detail:no_detail (store (Db.open_ ~database))
  in
  closing_on_error db (fun db ->
      let* (_ : int) = check_version log db in
      let+ (_ : string list) = check_tables log db in
      db)

let reopen log db database =
  let open Fut.Result_syntax in
  let* () = step log "close" ~detail:no_detail (store (Db.close db)) in
  let* db =
    step log "open again" ~detail:no_detail (store (Db.open_ ~database))
  in
  let* (_ : int list) =
    closing_on_error db (fun db ->
        let* (_ : int) = check_version log db in
        check_count log db)
  in
  step log "close" ~detail:no_detail (store (Db.close db))

type pragma

let version_row : (pragma, int) Row.t =
  Row.col {ty = Not_Null Integer; name = "user_version"}

(* The raw plugin's user_version, read without Db (which would migrate). *)
let raw_version raw =
  Fut.map
    (fun r ->
      Result.bind r (fun rows ->
          match rows with
          | [text] -> (
              match Codec.decode ~json:[] version_row text with
              | Ok v -> Ok v
              | Error e ->
                  Error
                    (Mismatch
                       {
                         expected = "a version row";
                         got = Codec.error_to_string e;
                       }))
          | _ ->
              Error
                (Mismatch
                   {expected = "1 row"; got = string_of_int (List.length rows)})))
    (plugin (Cap_sqlite.query raw "pragma user_version" []))

let expect_version expected fut =
  Fut.map
    (fun r ->
      Result.bind r (fun got ->
          match got = expected with
          | true -> Ok got
          | false ->
              Error
                (Mismatch
                   {expected = string_of_int expected; got = string_of_int got})))
    fut

(* Opens [database] with the plugin alone, runs [sql] on it if given, checks
   its version and closes it. *)
let prepare log database ~sql ~version =
  let open Fut.Result_syntax in
  let* raw =
    step log "connect (plugin)" ~detail:no_detail
      (plugin (Cap_sqlite.connect ~database))
  in
  let* () =
    step log "open (plugin)" ~detail:no_detail (plugin (Cap_sqlite.open_ raw))
  in
  let checks =
    let* () =
      match sql with
      | None -> Fut.ok ()
      | Some sql ->
          step log sql ~detail:no_detail
            (Fut.map
               (Result.map (fun (_ : int) -> ()))
               (plugin (Cap_sqlite.execute raw sql)))
    in
    let+ (_ : int) =
      step log
        (Printf.sprintf "user_version = %d (plugin)" version)
        ~detail:no_detail
        (expect_version version (raw_version raw))
    in
    ()
  in
  let* () =
    let open Fut.Syntax in
    let* checked = checks in
    match checked with
    | Ok () -> Fut.ok ()
    | Error e ->
        let+ (_ : (unit, Cap_error.t) result) = Cap_sqlite.close raw in
        Error e
  in
  step log "close (plugin)" ~detail:no_detail (plugin (Cap_sqlite.close raw))

(* An empty file at version 0, as an install that crashed before its first
   migration would leave. *)
let upgrade log database =
  let open Fut.Result_syntax in
  let* () = prepare log database ~sql:None ~version:0 in
  let* db = step log "open" ~detail:no_detail (store (Db.open_ ~database)) in
  let* (_ : string list) =
    closing_on_error db (fun db ->
        let* (_ : int) = check_version log db in
        check_tables log db)
  in
  step log "close" ~detail:no_detail (store (Db.close db))

let newer_version = Schema.latest + 1

let refused db_result =
  let expected =
    Db.error_to_string
      (Schema (Unknown_version {found = newer_version; latest = Schema.latest}))
  in
  match db_result with
  | Error (Db.Schema (Unknown_version {found; latest}))
    when found = newer_version && latest = Schema.latest ->
      Ok ()
  | Error e -> Error (Mismatch {expected; got = Db.error_to_string e})
  | Ok (_ : Db.t) -> Error (Mismatch {expected; got = "opened"})

(* A file written by a newer app: Db.open_ refuses it, and refuses it again,
   which shows the first refusal closed its connection. *)
let newer log database =
  let open Fut.Result_syntax in
  let* () =
    prepare log database
      ~sql:(Some (Printf.sprintf "pragma user_version = %d;\n" newer_version))
      ~version:newer_version
  in
  let* () =
    step log
      (Printf.sprintf "open refuses version %d" newer_version)
      ~detail:no_detail
      (Fut.map refused (Db.open_ ~database))
  in
  step log "open refuses it again" ~detail:no_detail
    (Fut.map refused (Db.open_ ~database))

let fresh_then_reuse log database =
  let open Fut.Result_syntax in
  heading log "fresh";
  let* db = fresh log database in
  heading log "round-trip";
  let* () = closing_on_error db (round_trip log) in
  heading log "reopen";
  reopen log db database

let run log =
  let open Fut.Syntax in
  let prefix = "herbier_dev_store_" ^ now () in
  let* (_ : (unit, failure) result) =
    fresh_then_reuse log (prefix ^ "_fresh")
  in
  heading log "upgrade from empty";
  let* (_ : (unit, failure) result) = upgrade log (prefix ^ "_empty") in
  heading log "newer version";
  let+ (_ : (unit, failure) result) = newer log (prefix ^ "_newer") in
  append log "done"

let el () =
  let log =
    Brr.El.div
      ~at:[Brr.At.v (Jstr.v "role") (Jstr.v "log")]
      [Brr.El.h1 [Brr.El.txt' "Store check"]]
  in
  Fut.await (run log) Fun.id;
  log
