module Cap_error = Herbier_bindings.Cap_error
module Cap_sqlite = Herbier_bindings.Cap_sqlite
module Fut_result = Herbier_bindings.Fut_result
module Db = Herbier_store_io.Db
module Codec = Herbier_store.Codec
module Schema = Herbier_store.Schema
module Plants = Herbier_store.Tables.Plants
module Plant_queries = Herbier_store.Plants
module Observation_queries = Herbier_store.Observations
module Outbox = Herbier_store.Outbox
module Search = Herbier_store.Search
module Settings = Herbier_store.Settings
module References = Herbier_store.References
module Reference = Herbier_domain.Reference
module Reference_id = Herbier_domain.Ids.Reference_id
module Row = Postgrest.Row
module Plant_id = Herbier_domain.Ids.Plant_id
module Photo_id = Herbier_domain.Ids.Photo_id
module Observation_id = Herbier_domain.Ids.Observation_id

type failure =
  | Store of Db.error
  | Plugin of Cap_error.t
  | Mismatch of {expected : string; got : string}

let failure_to_string = function
  | Store e -> Db.error_to_string e
  | Plugin e -> Cap_error.to_string e
  | Mismatch {expected; got} ->
      Printf.sprintf "expected %S, got %S" expected got

let store fut = Fut_result.map_error (fun e -> Store e) fut
let plugin fut = Fut_result.map_error (fun e -> Plugin e) fut
let no_detail _ = None
let step log label ~detail = Kit.step log label ~detail ~error:failure_to_string

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
type pragma_defer

let name_row : (master, string) Row.t =
  Row.col {ty = Not_Null Str; name = "name"}

let table_names =
  [
    "commune_packs";
    "observations";
    "outbox";
    "photo_original_targets";
    "photo_upload_states";
    "photos";
    "plant_refs";
    "plant_tags";
    "plants";
    "ref_images";
    "reference";
    "reference_organs";
    "reference_sources";
    "reference_statuses";
    "settings";
    "sync_state";
    "tags";
    "uploads";
  ]

let print_names = String.concat ", "

let check_tables log db =
  step log "tables"
    ~detail:(fun names -> Some (string_of_int (List.length names)))
    (expect print_names table_names
       (Db.query db ~json:[] name_row
          "select name from sqlite_master where type = 'table' and name not \
           like 'sqlite_%' and name not like 'plant_search%' order by name"
          []))

let check_version log db =
  step log
    (Printf.sprintf "user_version = %d" Schema.latest)
    ~detail:no_detail
    (expect string_of_int Schema.latest (Db.user_version db))

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

(* At least one row, not exactly one: the plugin's count includes the rows
   triggers write (an insert into plants also writes plant_search), so the
   steps after a write read its row back instead. *)
let expect_changed fut =
  Fut.map
    (fun r ->
      Result.bind r (function
        | n when n >= 1 -> Ok n
        | n ->
            Error
              (Mismatch {expected = ">= 1 row changed"; got = string_of_int n})))
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

let search_plant display_name scientific_name : Herbier_domain.Plant.t =
  {
    id = Plant_id.fresh ();
    display_name;
    aliases = [];
    scientific_name;
    authorship = None;
    gbif_key = None;
    notes = "";
    notes_updated_at = None;
    cover_photo_id = None;
    created_at = time "2026-10-28T15:00:00Z";
    updated_at = time "2026-10-28T15:00:00Z";
    deleted_at = None;
  }

let display_names =
  List.map (fun (p : Herbier_domain.Plant.t) -> p.display_name)

(* Through the real plugin, this shows that migration 2's FTS5 table and
   triggers exist on the device and keep the index in sync. *)
let check_search log db =
  let open Fut.Result_syntax in
  let* (_ : int) =
    step log "edit: upsert 2 plants" ~detail:no_detail
      (expect string_of_int 2
         (Db.edit db
            [
              Plant_queries.upsert
                (search_plant "Digitale pourpre" (Some "Digitalis purpurea"));
              Plant_queries.upsert (search_plant "Digitalis" None);
            ]))
  in
  let found =
    match Search.plants "digitale" with
    | None -> Fut.ok []
    | Some q -> Fut.map (Result.map display_names) (Db.all db q)
  in
  step log "search \"digitale\""
    ~detail:(fun names -> Some (print_names names))
    (expect print_names ["Digitale pourpre"; "Digitalis"] found)

let check_wifi_only log db expected =
  step log
    ("settings: wifi_only = " ^ string_of_bool expected)
    ~detail:no_detail
    (expect
       (function None -> "none" | Some b -> string_of_bool b)
       (Some expected)
       (Db.find db (Settings.get Wifi_only)))

let check_settings log db =
  let open Fut.Result_syntax in
  let* (_ : int) =
    step log "settings: wifi_only := true" ~detail:no_detail
      (expect_changed (Db.write db (Settings.set Wifi_only true)))
  in
  check_wifi_only log db true

type count

let count_row : (count, int) Row.t = Row.col {ty = Not_Null Integer; name = "n"}
let print_ints rows = String.concat ", " (List.map string_of_int rows)

(* 2 from round-trip, 2 from search, 3 from the outbox group, 1 from the
   references group, 1 from the bare transaction group. *)
let check_count log db =
  step log "9 plants rows" ~detail:no_detail
    (expect print_ints [9]
       (Db.query db ~json:[] count_row "select count(*) as n from plants" []))

let outbox_count db = Db.all db Outbox.count

let check_outbox_count log db n =
  step log
    (Printf.sprintf "%d outbox entries" n)
    ~detail:no_detail
    (expect print_ints [n] (outbox_count db))

let print_entries entries =
  String.concat ", "
    (List.map
       (fun (e : Outbox.entry) ->
         Printf.sprintf "%d %s %s" (Outbox.seq_to_int e.seq) e.table_name
           e.row_id)
       entries)

let last_two entries =
  match List.rev entries with b :: a :: _ -> [a; b] | [] | [_] -> []

(* Both edits' entries come last, in order, for plants a and b. *)
let expect_appended (a : Herbier_domain.Plant.t) (b : Herbier_domain.Plant.t)
    fut =
  let ids = [Plant_id.to_string a.id; Plant_id.to_string b.id] in
  Fut.map
    (fun r ->
      Result.bind r (fun entries ->
          match
            List.map
              (fun (e : Outbox.entry) -> (e.table_name, e.row_id))
              (last_two entries)
          with
          | got when got = List.map (fun id -> ("plants", id)) ids -> Ok entries
          | (_ : (string * string) list) ->
              Error
                (Mismatch
                   {
                     expected = "last: plants " ^ String.concat ", plants " ids;
                     got = print_entries entries;
                   })))
    (store fut)

(* [error] picks the expected error, as the text the step shows. *)
let expect_error ~expected error fut =
  Fut.map
    (function
      | Ok n -> Error (Mismatch {expected; got = Printf.sprintf "Ok %d" n})
      | Error e -> (
          match error e with
          | Some text -> Ok text
          | None -> Error (Mismatch {expected; got = Db.error_to_string e})))
    fut

let expect_plugin_error =
  expect_error ~expected:"a plugin error" (function
    | Db.Plugin e -> Some (Cap_error.to_string e)
    | Decode _ | Schema _ | Migration _ | Not_migrated _ | Unexpected_rows _
    | Foreign_key _ | Raised _ ->
        None)

let expect_foreign_key =
  expect_error ~expected:"a foreign key error" (function
    | Db.Foreign_key _ as e -> Some (Db.error_to_string e)
    | Plugin _ | Decode _ | Schema _ | Migration _ | Not_migrated _
    | Unexpected_rows _ | Raised _ ->
        None)

let orphan_observation () : Herbier_domain.Observation.t =
  {
    id = Observation_id.fresh ();
    plant_id = Some (Plant_id.fresh ());
    at = time "2026-10-28T16:00:00Z";
    position = None;
    place_label = None;
    place_derived = None;
    note = None;
    created_at = time "2026-10-28T16:00:00Z";
    updated_at = time "2026-10-28T16:00:00Z";
    deleted_at = None;
  }

let plant_present db (p : Herbier_domain.Plant.t) expected =
  expect
    (function true -> "present" | false -> "absent")
    expected
    (Fut.map (Result.map Option.is_some) (Db.find db (Plant_queries.get p.id)))

(* The explicit transaction, its rollback and Db's serialisation only exist
   on the device. *)
let check_outbox log db =
  let open Fut.Result_syntax in
  let a = search_plant "Outbox A" None and b = search_plant "Outbox B" None in
  let* (_ : int list) = check_outbox_count log db 2 in
  let* (_ : int) =
    step log "edit: upsert a, b" ~detail:no_detail
      (expect string_of_int 2
         (Db.edit db [Plant_queries.upsert a; Plant_queries.upsert b]))
  in
  let* entries =
    step log "next lists a, b last"
      ~detail:(fun entries -> Some (print_entries entries))
      (expect_appended a b (Db.all db (Outbox.next ~limit:10)))
  in
  let c = search_plant "Outbox C" None in
  let* (_ : string) =
    step log "edit: c + orphan observation fails"
      ~detail:(fun e -> Some e)
      (expect_plugin_error
         (Db.edit db
            [
              Plant_queries.upsert c;
              Observation_queries.upsert (orphan_observation ());
            ]))
  in
  let* (_ : bool) =
    step log "c rolled back" ~detail:no_detail (plant_present db c false)
  in
  let* (_ : int list) = check_outbox_count log db 4 in
  let* (_ : int) =
    step log "write after rollback" ~detail:no_detail
      (expect_changed (Db.write db (Settings.set Wifi_only true)))
  in
  let d = search_plant "Outbox D" None in
  let edited = Db.edit db [Plant_queries.upsert d] in
  let written = Db.write db (Settings.set Wifi_only false) in
  let* (_ : int) =
    step log "overlapping edit" ~detail:no_detail
      (expect string_of_int 1 edited)
  in
  let* (_ : int) =
    step log "overlapping write" ~detail:no_detail (expect_changed written)
  in
  let* (_ : bool) =
    step log "d present" ~detail:no_detail (plant_present db d true)
  in
  let* (_ : int list) = check_outbox_count log db 5 in
  match entries with
  | [] -> Fut.error (Mismatch {expected = "an entry"; got = "none"})
  | (first : Outbox.entry) :: _ ->
      let* (_ : int) =
        step log "park first" ~detail:no_detail
          (expect_changed (Db.write db (Outbox.park first.seq ~error:"test")))
      in
      let* (_ : string list) =
        step log "next skips it" ~detail:no_detail
          (expect print_names []
             (Fut.map
                (Result.map (fun entries ->
                     List.filter_map
                       (fun (e : Outbox.entry) ->
                         match
                           Int.equal (Outbox.seq_to_int e.seq)
                             (Outbox.seq_to_int first.seq)
                         with
                         | true -> Some e.row_id
                         | false -> None)
                       entries))
                (Db.all db (Outbox.next ~limit:10))))
      in
      let* (_ : int) =
        step log "delete first" ~detail:no_detail
          (expect_changed (Db.write db (Outbox.delete first.seq)))
      in
      check_outbox_count log db 4

(* The payload column holds JSON text that only the device's plugin stores
   and returns: test/store cannot show it round-trips there. An [`Intlit]
   because js_of_ocaml reads an occurrence key above 2^31 back as one. *)
let reference_payload n =
  `Assoc
    [
      ( "species",
        `Assoc
          [
            ("key", `Int 5414995);
            ("vernacularName", `String "Digitale pourprée");
            ("results", `List [`Assoc [("key", `Intlit "5110295086")]; `Null]);
          ] );
      ("occurrence_count", `Int n);
    ]

let expect_reference ~id ~payload ~updated_at fut =
  Fut.map
    (fun r ->
      Result.bind r (function
        | Some (got : Reference.t)
          when Reference_id.equal got.id id
               && Yojson.Safe.equal got.payload payload
               && Ptime.equal got.updated_at updated_at ->
            Ok got
        | Some got ->
            Error
              (Mismatch
                 {
                   expected = Yojson.Safe.to_string payload;
                   got =
                     Printf.sprintf "%s %s %s"
                       (Reference_id.to_string got.id)
                       (Ptime.to_rfc3339 got.updated_at)
                       (Yojson.Safe.to_string got.payload);
                 })
        | None -> Error (Mismatch {expected = "a row"; got = "none"})))
    (store fut)

let check_references log db =
  let open Fut.Result_syntax in
  let p = search_plant "References" None in
  let plant = p.id in
  let t1 = time "2026-10-28T17:00:00Z" and t2 = time "2026-10-28T18:00:00Z" in
  let id = Reference.id_of_key ~plant ~source:Gbif in
  let put n at =
    References.put ~plant ~source:Gbif ~fetched_at:at
      ~payload:(reference_payload n) ~status:Complete ~at
  in
  let entries n label edits =
    step log label ~detail:no_detail (expect string_of_int n (Db.edit db edits))
  in
  let* (_ : int) = entries 1 "edit: plant" [Plant_queries.upsert p] in
  let* (_ : int) = entries 1 "put gbif" [put 1 t1] in
  let* (_ : Reference.t) =
    step log "get = put" ~detail:no_detail
      (expect_reference ~id ~payload:(reference_payload 1) ~updated_at:t1
         (Db.find db (References.get plant Gbif)))
  in
  let* (_ : int) = entries 1 "put gbif again" [put 2 t2] in
  let* (_ : Reference.t) =
    step log "same id, new payload, updated_at moved" ~detail:no_detail
      (expect_reference ~id ~payload:(reference_payload 2) ~updated_at:t2
         (Db.find db (References.get plant Gbif)))
  in
  let link =
    References.link ~plant ~source:Gbif ~external_id:"5414995"
      ~url:"https://www.gbif.org/species/5414995" ~at:t1
  in
  let* (_ : int) = entries 1 "link" [link] in
  let* (_ : int) = entries 0 "same link" [link] in
  let* (_ : int) =
    entries 1 "unlink" [References.unlink ~plant ~source:Gbif ~at:t2]
  in
  step log "last outbox entries"
    ~detail:(fun names -> Some (print_names names))
    (expect print_names
       ["plants"; "reference"; "reference"; "plant_refs"; "plant_refs"]
       (Fut.map
          (Result.map (fun entries ->
               List.map (fun (e : Outbox.entry) -> e.table_name) entries
               |> List.rev
               |> List.take 5
               |> List.rev))
          (Db.all db (Outbox.next ~limit:100))))

let defer_row : (pragma_defer, int) Row.t =
  Row.col {ty = Not_Null Integer; name = "defer_foreign_keys"}

let defer_query =
  Herbier_store.Stmt.query ~json:[] defer_row "pragma defer_foreign_keys" []

let observation_present db (o : Herbier_domain.Observation.t) expected =
  expect
    (function true -> "present" | false -> "absent")
    expected
    (Fut.map
       (Result.map Option.is_some)
       (Db.find db (Observation_queries.get o.id)))

let bare_write tx edit = Db.Tx.write tx (Outbox.without_entry edit)

(* Deferred foreign keys, the pragma and the rollback after a violation are
   the plugin's: only the device runs them. *)
let check_bare log db =
  let open Fut.Result_syntax in
  let* before = store (outbox_count db) in
  let p = search_plant "Bare" None in
  let o = {(orphan_observation ()) with plant_id = Some p.id} in
  let* (_ : int list) =
    step log "child before parent commits"
      ~detail:(fun d -> Some ("defer_foreign_keys inside: " ^ print_ints d))
      (expect print_ints [1]
         (Db.bare_transaction db (fun tx ->
              let* (_ : int) = bare_write tx (Observation_queries.upsert o) in
              let* (_ : int) = bare_write tx (Plant_queries.upsert p) in
              Db.Tx.all tx defer_query)))
  in
  let* (_ : bool) =
    step log "plant present" ~detail:no_detail (plant_present db p true)
  in
  let* (_ : bool) =
    step log "observation present" ~detail:no_detail
      (observation_present db o true)
  in
  let* (_ : int list) =
    step log "no entry appended" ~detail:no_detail
      (expect print_ints before (outbox_count db))
  in
  let* (_ : int list) =
    step log "defer_foreign_keys after commit" ~detail:no_detail
      (expect print_ints [0] (Db.all db defer_query))
  in
  let orphan = orphan_observation () in
  let* (_ : string) =
    step log "orphan fails before commit"
      ~detail:(fun e -> Some e)
      (expect_foreign_key
         (Db.bare_transaction db (fun tx ->
              bare_write tx (Observation_queries.upsert orphan))))
  in
  let* (_ : bool) =
    step log "orphan rolled back" ~detail:no_detail
      (observation_present db orphan false)
  in
  step log "write after rollback" ~detail:no_detail
    (expect_changed (Db.write db (Settings.set Wifi_only false)))

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
  let* (_ : bool option) =
    closing_on_error db (fun db ->
        let* (_ : int) = check_version log db in
        let* (_ : int list) = check_count log db in
        (* The last setting written before the close (the outbox group's
           overlapping write) survives it. *)
        check_wifi_only log db false)
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
  Kit.heading log "fresh";
  let* db = fresh log database in
  Kit.heading log "round-trip";
  let* () = closing_on_error db (round_trip log) in
  Kit.heading log "search";
  let* (_ : string list) = closing_on_error db (check_search log) in
  Kit.heading log "settings";
  let* (_ : bool option) = closing_on_error db (check_settings log) in
  Kit.heading log "outbox";
  let* (_ : int list) = closing_on_error db (check_outbox log) in
  Kit.heading log "references";
  let* (_ : string list) = closing_on_error db (check_references log) in
  Kit.heading log "transaction sans entrée";
  let* (_ : int) = closing_on_error db (check_bare log) in
  Kit.heading log "reopen";
  reopen log db database

let run log =
  let open Fut.Syntax in
  let prefix = "herbier_dev_store_" ^ now () in
  let* (_ : (unit, failure) result) =
    fresh_then_reuse log (prefix ^ "_fresh")
  in
  Kit.heading log "upgrade from empty";
  let* (_ : (unit, failure) result) = upgrade log (prefix ^ "_empty") in
  Kit.heading log "newer version";
  let+ (_ : (unit, failure) result) = newer log (prefix ^ "_newer") in
  Kit.append log "done"

let el () =
  let log =
    Brr.El.div
      ~at:[Brr.At.v (Jstr.v "role") (Jstr.v "log")]
      [Brr.El.h1 [Brr.El.txt' "Store check"]]
  in
  Fut.await (run log) Fun.id;
  log
