module Cap_error = Herbier_bindings.Cap_error
module Cap_preferences = Herbier_bindings.Cap_preferences
module Cap_filesystem = Herbier_bindings.Cap_filesystem
module Cap_sqlite = Herbier_bindings.Cap_sqlite
module Cap_app = Herbier_bindings.Cap_app

type failure =
  | Plugin of Cap_error.t
  | Mismatch of {expected : string; got : string}

let failure_to_string = function
  | Plugin e -> Cap_error.to_string e
  | Mismatch {expected; got} ->
      Printf.sprintf "expected %S, got %S" expected got

let append log text = Brr.El.append_children log [Brr.El.div [Brr.El.txt' text]]
let heading log text = Brr.El.append_children log [Brr.El.h2 [Brr.El.txt' text]]
let plugin fut = Fut.map (Result.map_error (fun e -> Plugin e)) fut
let no_detail _ = ""

(* Reports the step as soon as it settles and passes its result on, so a
   group's chain stops at its first failure while every outcome is shown. *)
let step log label ~detail fut =
  Fut.map
    (fun r ->
      (match r with
      | Ok v -> (
          match detail v with
          | "" -> append log (label ^ ": ok")
          | d -> append log (label ^ ": ok · " ^ d))
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
    (plugin fut)

let print_option = function None -> "none" | Some s -> s

let now () =
  let p = Brr.G.performance in
  Brr.Performance.time_origin_ms p +. Brr.Performance.now_ms p
  |> Printf.sprintf "%.0f"

let preferences log =
  let open Fut.Result_syntax in
  let key = "herbier.dev.check" in
  let value = "check " ^ now () in
  let* () =
    step log "set" ~detail:no_detail (plugin (Cap_preferences.set ~key ~value))
  in
  let* (_ : string option) =
    step log "get = value" ~detail:print_option
      (expect print_option (Some value) (Cap_preferences.get ~key))
  in
  let* () =
    step log "remove" ~detail:no_detail (plugin (Cap_preferences.remove ~key))
  in
  step log "get = none" ~detail:print_option
    (expect print_option None (Cap_preferences.get ~key))

(* Bytes 0x00–0xFF, base64-encoded. *)
let all_bytes =
  "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0+P0BBQkNERUZHSElKS0xNTk9QUVJTVFVWV1hZWltcXV5fYGFiY2RlZmdoaWprbG1ub3BxcnN0dXZ3eHl6e3x9fn+AgYKDhIWGh4iJiouMjY6PkJGSk5SVlpeYmZqbnJ2en6ChoqOkpaanqKmqq6ytrq+wsbKztLW2t7i5uru8vb6/wMHCw8TFxsfIycrLzM3Oz9DR0tPU1dbX2Nna29zd3t/g4eLj5OXm5+jp6uvs7e7v8PHy8/T19vf4+fr7/P3+/w=="

(* The read after delete must fail; its error is shown verbatim because the
   binding does not interpret it. *)
let expect_error fut =
  Fut.map
    (function
      | Ok got -> Error (Mismatch {expected = "an error"; got})
      | Error e -> Ok (Cap_error.to_string e))
    fut

let filesystem log =
  let open Fut.Result_syntax in
  let text = "Digitale pourpre · ✓ " ^ now () in
  let txt = "dev/check.txt" and bin = "dev/check.bin" in
  let* () =
    (* An existing directory is a reported error, not a failed group. *)
    Fut.map
      (fun (_ : (unit, failure) result) -> Ok ())
      (step log "mkdir dev" ~detail:no_detail
         (plugin (Cap_filesystem.mkdir ~path:"dev" ~recursive:true)))
  in
  let* (_ : string) =
    step log "write_text" ~detail:Fun.id
      (plugin (Cap_filesystem.write_text ~path:txt text))
  in
  let* (_ : string) =
    step log "read_text = written" ~detail:no_detail
      (expect Fun.id text (Cap_filesystem.read_text ~path:txt))
  in
  let* (_ : string) =
    step log "write_base64" ~detail:Fun.id
      (plugin (Cap_filesystem.write_base64 ~path:bin all_bytes))
  in
  let* (_ : string) =
    step log "read_base64 = written" ~detail:no_detail
      (expect Fun.id all_bytes (Cap_filesystem.read_base64 ~path:bin))
  in
  let* () =
    step log "delete text" ~detail:no_detail
      (plugin (Cap_filesystem.delete_file ~path:txt))
  in
  let* () =
    step log "delete binary" ~detail:no_detail
      (plugin (Cap_filesystem.delete_file ~path:bin))
  in
  step log "read after delete fails" ~detail:Fun.id
    (expect_error (Cap_filesystem.read_text ~path:txt))

let contains ~sub s =
  Option.is_some (Jstr.find_sub ~sub:(Jstr.v sub) (Jstr.v s))

let expect_row fut =
  Fut.map
    (fun r ->
      Result.bind r (fun rows ->
          match
            List.find_opt
              (fun row ->
                contains ~sub:{|"label":"Digitale pourpre"|} row
                && contains ~sub:{|"n":null|} row)
              rows
          with
          | Some row -> Ok row
          | None ->
              Error
                (Mismatch
                   {
                     expected =
                       {|a row with "label":"Digitale pourpre" and "n":null|};
                     got = String.concat ", " rows;
                   })))
    (plugin fut)

let expect_one_change fut =
  Fut.map
    (fun r ->
      Result.bind r (fun ({Cap_sqlite.changed; last_id = _} as c) ->
          match changed with
          | 1 -> Ok c
          | n ->
              Error
                (Mismatch {expected = "1 row changed"; got = string_of_int n})))
    (plugin fut)

let print_last_id {Cap_sqlite.last_id; changed = _} =
  "last_id " ^ print_option (Option.map string_of_int last_id)

let sqlite log =
  let open Fut.Result_syntax in
  let label = Cap_sqlite.Text "Digitale pourpre" in
  let* db =
    step log "connect" ~detail:no_detail
      (plugin (Cap_sqlite.connect ~database:"herbier_dev"))
  in
  let* () = step log "open" ~detail:no_detail (plugin (Cap_sqlite.open_ db)) in
  let* (_ : int) =
    step log "create table" ~detail:no_detail
      (plugin
         (Cap_sqlite.execute db
            "create table if not exists dev_check (id integer primary key, \
             label text not null, x real, n integer)"))
  in
  let* (_ : Cap_sqlite.changes) =
    step log "insert" ~detail:print_last_id
      (expect_one_change
         (Cap_sqlite.run db
            "insert into dev_check (label, x, n) values (?, ?, ?)"
            [label; Float 45.5; Null]))
  in
  let* (_ : string) =
    step log "query" ~detail:Fun.id
      (expect_row
         (Cap_sqlite.query db
            "select label, x, n from dev_check where label = ?" [label]))
  in
  let* (_ : int) =
    step log "drop table" ~detail:no_detail
      (plugin (Cap_sqlite.execute db "drop table dev_check"))
  in
  step log "close" ~detail:no_detail (plugin (Cap_sqlite.close db))

let state_label = function
  | Cap_app.Active -> "active"
  | Cap_app.Inactive -> "inactive"

(* The state listener stays registered for the life of the page, so that
   backgrounding the app shows its lines. *)
let app log =
  let open Fut.Result_syntax in
  let* (_ : Cap_app.listener) =
    step log "on_state_change" ~detail:no_detail
      (plugin
         (Cap_app.on_state_change (fun s ->
              append log ("state: " ^ state_label s))))
  in
  let* url =
    step log "on_url_open" ~detail:no_detail
      (plugin (Cap_app.on_url_open (fun u -> append log ("url: " ^ u))))
  in
  step log "remove url listener" ~detail:no_detail (plugin (Cap_app.remove url))

let run log =
  let open Fut.Syntax in
  heading log "preferences";
  let* (_ : (string option, failure) result) = preferences log in
  heading log "filesystem";
  let* (_ : (string, failure) result) = filesystem log in
  heading log "sqlite";
  let* (_ : (unit, failure) result) = sqlite log in
  heading log "app";
  let+ (_ : (unit, failure) result) = app log in
  append log "done"

let el () =
  let log =
    Brr.El.div
      ~at:[Brr.At.v (Jstr.v "role") (Jstr.v "log")]
      [Brr.El.h1 [Brr.El.txt' "Storage check"]]
  in
  Fut.await (run log) Fun.id;
  log
