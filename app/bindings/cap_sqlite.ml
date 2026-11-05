type t = {conn : Jv.t; database : string}
type value = Null | Int of int | Float of float | Text of string
type changes = {changed : int; last_id : int option}

let plugin = "sqlite"
let unit_ok = Cap_call.unit_ok

let jv_of_value = function
  | Null -> Jv.null
  | Int n -> Jv.of_int n
  | Float f -> Jv.of_float f
  | Text s -> Jv.of_string s

(* The wrapper rejects a second createConnection for a name it already
   holds, which is the normal state after a WebView reload: consistency
   check first (it drops native connections the reloaded JS side no longer
   knows), then retrieveConnection if isConnection says one exists, else
   createConnection (the plugin's documented sequence). *)
let connect ~database =
  let open Fut.Result_syntax in
  let name = Jv.of_string database in
  let read_only = Jv.false' in
  let as_conn conn = Ok {conn; database} in
  let* () =
    Cap_call.call plugin "checkConnectionsConsistency" [||] ~ok:unit_ok
  in
  let* exists =
    Cap_call.call plugin "isConnection" [|name; read_only|] ~ok:(fun r ->
        Cap_call.bool_field r "result")
  in
  match exists with
  | true ->
      Cap_call.call plugin "retrieveConnection" [|name; read_only|] ~ok:as_conn
  | false ->
      Cap_call.call plugin "createConnection"
        [|
          name; Jv.false'; Jv.of_string "no-encryption"; Jv.of_int 1; read_only;
        |]
        ~ok:as_conn

let open_ {conn; database = _} = Cap_call.on conn "open" [||] ~ok:unit_ok

(* closeConnection runs even when close fails, so the wrapper does not keep
   a half-closed connection that the next connect would retrieve. *)
let close {conn; database} =
  let open Fut.Syntax in
  let* closed = Cap_call.on conn "close" [||] ~ok:unit_ok in
  let+ released =
    Cap_call.call plugin "closeConnection"
      [|Jv.of_string database; Jv.false'|]
      ~ok:unit_ok
  in
  Result.bind closed (fun () -> released)

let execute {conn; database = _} sql =
  Cap_call.on conn "execute"
    [|Jv.of_string sql|]
    ~ok:(fun r -> Cap_call.int_field r "changes.changes")

let params values = Jv.of_list jv_of_value values

(* The Android side reads [values] of every element unconditionally, so it is
   sent even when empty. *)
let execute_set {conn; database = _} statements =
  let element sql =
    Jv.obj [|("statement", Jv.of_string sql); ("values", Jv.of_jv_array [||])|]
  in
  Cap_call.on conn "executeSet"
    [|Jv.of_list element statements; Jv.true'|]
    ~ok:(fun r -> Cap_call.int_field r "changes.changes")

(* JSON.stringify throws on a BigInt or a cycle and gives undefined for
   undefined; [ok] runs in a promise callback and must not raise. *)
let json_text row =
  match Jv.of_jstr (Brr.Json.encode row) with
  | s when Jstr.equal (Jv.typeof s) (Jstr.v "string") -> Ok (Jv.to_string s)
  | (_ : Jv.t) -> Error (Cap_error.Unexpected "values")
  | exception Jv.Error _ -> Error (Cap_error.Unexpected "values")

let all_ok results =
  List.fold_right
    (fun r acc -> Result.bind r (fun x -> Result.map (List.cons x) acc))
    results (Ok [])

let run ?(transaction = true) {conn; database = _} sql values =
  Cap_call.on conn "run"
    [|Jv.of_string sql; params values; Jv.of_bool transaction|]
    ~ok:(fun r ->
      Result.map
        (fun changed ->
          {
            changed;
            last_id = Result.to_option (Cap_call.int_field r "changes.lastId");
          })
        (Cap_call.int_field r "changes.changes"))

let begin_transaction {conn; database = _} =
  Cap_call.on conn "beginTransaction" [||] ~ok:unit_ok

let commit_transaction {conn; database = _} =
  Cap_call.on conn "commitTransaction" [||] ~ok:unit_ok

let rollback_transaction {conn; database = _} =
  Cap_call.on conn "rollbackTransaction" [||] ~ok:unit_ok

let query {conn; database = _} sql values =
  Cap_call.on conn "query"
    [|Jv.of_string sql; params values|]
    ~ok:(fun r ->
      match Cap_call.field r "values" with
      | Ok rows when Jv.is_array rows ->
          Jv.to_list Fun.id rows |> List.map json_text |> all_ok
      | Ok _ | Error _ -> Error (Cap_error.Unexpected "values"))
