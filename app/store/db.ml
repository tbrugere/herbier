module Cap_error = Herbier_bindings.Cap_error
module Cap_sqlite = Herbier_bindings.Cap_sqlite

(* style: mutable field because the plugin forces it (style 2.2): a
   statement run while an explicit transaction is open ends that transaction
   (the plugin's own per-call transaction fails and rolls back the caller's),
   so operations on a connection are chained, each starting once [tail], the
   previous one, has settled. Hidden behind the abstract [t]. *)
type t = {conn : Cap_sqlite.t; mutable tail : unit Fut.t}

type error =
  | Plugin of Cap_error.t
  | Decode of {sql : string; row : int; error : Codec.error}
  | Schema of Schema.error
  | Migration of {version : int; error : Cap_error.t}
  | Not_migrated of {expected : int; found : int}
  | Unexpected_rows of {sql : string; count : int}
  | Raised of string

let error_to_string = function
  | Plugin e -> Cap_error.to_string e
  | Decode {sql; row; error} ->
      Printf.sprintf "row %d of %S: %s" row sql (Codec.error_to_string error)
  | Schema (Unknown_version {found; latest}) ->
      Printf.sprintf "database version %d unknown (this app knows up to %d)"
        found latest
  | Migration {version; error} ->
      Printf.sprintf "migration %d failed: %s" version
        (Cap_error.to_string error)
  | Not_migrated {expected; found} ->
      Printf.sprintf "database at version %d after migrating, expected %d" found
        expected
  | Unexpected_rows {sql; count} ->
      Printf.sprintf "%S returned %d rows, expected one" sql count
  | Raised exn -> Printf.sprintf "raised %s" exn

let plugin fut = Fut.map (Result.map_error (fun e -> Plugin e)) fut

let value = function
  | Codec.Null -> Cap_sqlite.Null
  | Int i -> Int i
  | Float f -> Float f
  | Text s -> Text s

let values params = List.map value params

let run_on ?transaction conn sql params =
  plugin
    (Fut.map
       (Result.map (fun {Cap_sqlite.changed; last_id = _} -> changed))
       (Cap_sqlite.run ?transaction conn sql (values params)))

let decode_rows decode sql rows =
  let rec go acc i = function
    | [] -> Ok (List.rev acc)
    | text :: rest -> (
        match decode text with
        | Ok v -> go (v :: acc) (i + 1) rest
        | Error error -> Error (Decode {sql; row = i; error}))
  in
  go [] 0 rows

let all_on conn q =
  let {Stmt.sql; params} = Stmt.stmt q in
  Fut.map
    (fun r -> Result.bind r (decode_rows (Stmt.decode q) sql))
    (plugin (Cap_sqlite.query conn sql (values params)))

type pragma

let user_version_row : (pragma, int) Postgrest.Row.t =
  Postgrest.Row.col {ty = Not_Null Integer; name = "user_version"}

let user_version_on conn =
  let sql = "pragma user_version" in
  Fut.map
    (fun r ->
      Result.bind r (function
        | [version] -> Ok version
        | ([] | _ :: _ :: _) as rows ->
            Error (Unexpected_rows {sql; count = List.length rows})))
    (all_on conn (Stmt.query ~json:[] user_version_row sql []))

let migrate db migrations =
  let open Fut.Result_syntax in
  let rec go = function
    | [] -> Fut.ok ()
    | (m : Schema.migration) :: rest ->
        let* (_ : int) =
          Fut.map
            (Result.map_error (fun error ->
                 Migration {version = m.version; error}))
            (Cap_sqlite.execute_set db (Schema.batch m))
        in
        go rest
  in
  go migrations

let open_and_migrate db =
  let open Fut.Result_syntax in
  let* () = plugin (Cap_sqlite.open_ db) in
  let* current = user_version_on db in
  let* migrations =
    Fut.return (Result.map_error (fun e -> Schema e) (Schema.pending ~current))
  in
  let* () = migrate db migrations in
  let* found = user_version_on db in
  match found = Schema.latest with
  | true -> Fut.ok {conn = db; tail = Fut.return ()}
  | false -> Fut.error (Not_migrated {expected = Schema.latest; found})

let open_ ~database =
  let open Fut.Syntax in
  let* connected = Cap_sqlite.connect ~database in
  match connected with
  | Error e -> Fut.error (Plugin e)
  | Ok db -> (
      let* opened = open_and_migrate db in
      match opened with
      | Ok db -> Fut.ok db
      | Error e ->
          (* The first error is the one worth reporting; a close failure on
             top of it says nothing new. *)
          let+ (_ : (unit, Cap_error.t) result) = Cap_sqlite.close db in
          Error e)

(* Runs [f conn] once the previous operation on [db] has settled; the next
   one waits for this one. Fut never fails, and a raise while starting [f] is
   turned into [Raised], so the chain cannot break on either. A raise inside
   one of [f]'s own continuations would leave its future, and so every later
   operation, pending: [f] relies on Cap_call and Codec never raising. *)
let queued db f =
  let start () =
    match f db.conn with
    | fut -> fut
    | exception exn -> Fut.error (Raised (Printexc.to_string exn))
  in
  let fut = Fut.bind db.tail start in
  db.tail <- Fut.map (fun (_ : (_, error) result) -> ()) fut;
  fut

let close db = queued db (fun conn -> plugin (Cap_sqlite.close conn))
let user_version db = queued db user_version_on

let exec db statements =
  queued db (fun conn ->
      plugin
        (Fut.map
           (Result.map (fun (_ : int) -> ()))
           (Cap_sqlite.execute_set conn statements)))

let run db sql params = queued db (fun conn -> run_on conn sql params)
let all db q = queued db (fun conn -> all_on conn q)
let query db ~json spec sql params = all db (Stmt.query ~json spec sql params)

let find db q =
  let {Stmt.sql; params = _} = Stmt.stmt q in
  Fut.map
    (fun r ->
      Result.bind r (function
        | [] -> Ok None
        | [v] -> Ok (Some v)
        | _ :: _ :: _ as rows ->
            Error (Unexpected_rows {sql; count = List.length rows})))
    (all db q)

let write db {Stmt.sql; params} = run db sql params

let write_all db stmts =
  queued db (fun conn ->
      let open Fut.Result_syntax in
      let rec go = function
        | [] -> Fut.ok ()
        | {Stmt.sql; params} :: rest ->
            let* (_ : int) = run_on conn sql params in
            go rest
      in
      go stmts)

let one_row sql = function
  | [text] -> Ok text
  | ([] | _ :: _ :: _) as rows ->
      Error (Unexpected_rows {sql; count = List.length rows})

(* Inside the explicit transaction every statement passes
   ~transaction:false: the plugin's own transaction would fail on the open
   one and roll it back. *)
let apply conn edits =
  let open Fut.Result_syntax in
  let rec go appended = function
    | [] -> Fut.ok appended
    | e :: rest -> (
        let {Stmt.sql; params} = Outbox.without_entry e in
        let* changed = run_on ~transaction:false conn sql params in
        match changed with
        | 0 -> go appended rest
        | _ ->
            let {Stmt.sql; params} = Outbox.reread e in
            let* rows = plugin (Cap_sqlite.query conn sql (values params)) in
            let* text = Fut.return (one_row sql rows) in
            let* entry =
              Fut.return
                (Result.map_error
                   (fun error -> Decode {sql; row = 0; error})
                   (Outbox.append e text))
            in
            let* (_ : int) =
              run_on ~transaction:false conn entry.sql entry.params
            in
            go (appended + 1) rest)
  in
  go 0 edits

let in_transaction conn edits =
  let open Fut.Syntax in
  let* begun = plugin (Cap_sqlite.begin_transaction conn) in
  match begun with
  | Error e -> Fut.error e
  | Ok () -> (
      let* applied = apply conn edits in
      let* committed =
        match applied with
        | Error e -> Fut.error e
        | Ok appended ->
            Fut.map
              (Result.map (fun () -> appended))
              (plugin (Cap_sqlite.commit_transaction conn))
      in
      match committed with
      | Ok appended -> Fut.ok appended
      | Error e ->
          (* The first error is the one returned; a failed rollback may
             leave the transaction open (the next begin then fails), so it
             is logged. *)
          let+ rolled_back = Cap_sqlite.rollback_transaction conn in
          (match rolled_back with
          | Ok () -> ()
          | Error r ->
              Brr.Console.(
                error
                  [
                    str "Db.edit: rollback failed";
                    str (Cap_error.to_string r);
                    str "after";
                    str (error_to_string e);
                  ]));
          Error e)

let edit db = function
  | [] -> Fut.ok 0
  | _ :: _ as edits -> queued db (fun conn -> in_transaction conn edits)
