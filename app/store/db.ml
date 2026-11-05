module Cap_error = Herbier_bindings.Cap_error
module Cap_sqlite = Herbier_bindings.Cap_sqlite

type t = Cap_sqlite.t

type error =
  | Plugin of Cap_error.t
  | Decode of {sql : string; row : int; error : Codec.error}
  | Schema of Schema.error
  | Migration of {version : int; error : Cap_error.t}
  | Not_migrated of {expected : int; found : int}
  | Unexpected_rows of {sql : string; count : int}

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
      Printf.sprintf "%S returned %d rows, expected 1" sql count

let plugin fut = Fut.map (Result.map_error (fun e -> Plugin e)) fut

let value = function
  | Codec.Null -> Cap_sqlite.Null
  | Int i -> Int i
  | Float f -> Float f
  | Text s -> Text s

let exec db statements =
  plugin
    (Fut.map
       (Result.map (fun (_ : int) -> ()))
       (Cap_sqlite.execute_set db statements))

let run db sql params =
  plugin
    (Fut.map
       (Result.map (fun {Cap_sqlite.changed; last_id = _} -> changed))
       (Cap_sqlite.run db sql (List.map value params)))

let decode_rows ~json spec sql rows =
  let rec go acc i = function
    | [] -> Ok (List.rev acc)
    | text :: rest -> (
        match Codec.decode ~json spec text with
        | Ok v -> go (v :: acc) (i + 1) rest
        | Error error -> Error (Decode {sql; row = i; error}))
  in
  go [] 0 rows

let query db ~json spec sql params =
  Fut.map
    (fun r -> Result.bind r (decode_rows ~json spec sql))
    (plugin (Cap_sqlite.query db sql (List.map value params)))

type pragma

let user_version_row : (pragma, int) Postgrest.Row.t =
  Postgrest.Row.col {ty = Not_Null Integer; name = "user_version"}

let user_version db =
  let sql = "pragma user_version" in
  Fut.map
    (fun r ->
      Result.bind r (function
        | [version] -> Ok version
        | ([] | _ :: _ :: _) as rows ->
            Error (Unexpected_rows {sql; count = List.length rows})))
    (query db ~json:[] user_version_row sql [])

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
  let* current = user_version db in
  let* migrations =
    Fut.return (Result.map_error (fun e -> Schema e) (Schema.pending ~current))
  in
  let* () = migrate db migrations in
  let* found = user_version db in
  match found = Schema.latest with
  | true -> Fut.ok db
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

let close db = plugin (Cap_sqlite.close db)
