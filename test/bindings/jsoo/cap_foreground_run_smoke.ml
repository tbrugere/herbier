(* Herbier_bindings.Cap_foreground_run (app/bindings/cap_foreground_run.mli),
   under node, over the stub plugin of foreground_run_stub.js (preloaded by
   test/bindings/jsoo/dune): the wire shape start/update send (present keys
   only, [text] and [action] dropped when [None]), start's decoding of
   [notifications] and its [Unexpected] cases, rejections surfacing as
   [Rejected], stop's call, the ["interrupt"] listener's reason decoding and
   its removal, and the plugin-absent case. Silent on success; the first mismatch goes to
   stderr and exits 1 (smoke.ml's own pattern: process.exit leaves no room
   for a later future to overwrite the failure). *)

module Cap_foreground_run = Herbier_bindings.Cap_foreground_run
module Cap_error = Herbier_bindings.Cap_error

let process = Jv.get Jv.global "process"
let set_exit_code n = Jv.set process "exitCode" (Jv.of_int n)

let fail fmt =
  Printf.ksprintf
    (fun m ->
      prerr_endline m;
      Jv.call process "exit" [|Jv.of_int 1|] |> ignore)
    fmt

(* ---------- the stub's control surface ---------- *)

let set_start_json s = Jv.set Jv.global "__next_start_json" (Jv.of_string s)
let clear_error () = Jv.set Jv.global "__next_error" Jv.null

let set_error ~code message =
  Jv.set Jv.global "__next_error"
    (Jv.obj [|("code", Jv.of_string code); ("message", Jv.of_string message)|])

let empty_plugin_table () = Jv.set Jv.global "herbier" (Jv.obj [||])
let listener_name () = Jv.to_string (Jv.get Jv.global "__listener_name")
let fire json = Jv.call Jv.global "__fire" [|Jv.of_string json|] |> ignore

(* The stub's last call, as JSON.stringify([name, args]) recorded it. *)
let last_call () =
  match
    Yojson.Safe.from_string (Jv.to_string (Jv.get Jv.global "__last_call_json"))
  with
  | `List [`String name; `Assoc fields] -> (name, fields)
  | j ->
      fail "unexpected __last_call_json: %s" (Yojson.Safe.to_string j);
      ("", [])

let canonical fields =
  Yojson.Safe.to_string
    (`Assoc (List.sort (fun (a, _) (b, _) -> String.compare a b) fields))

(* Exact key set and values: a wrong value, an extra key or a missing key all
   fail. *)
let check_call what expected_name expected_fields =
  let name, fields = last_call () in
  (match String.equal expected_name name with
  | true -> ()
  | false -> fail "%s: call name expected %S, got %S" what expected_name name);
  let got = canonical fields and want = canonical expected_fields in
  match String.equal got want with
  | true -> ()
  | false -> fail "%s: expected args %s, got %s" what want got

(* ---------- rendering (diagnostics and equality both) ---------- *)

let string_of_notifications : Cap_foreground_run.notifications -> string =
  function
  | Granted -> "Granted"
  | Denied -> "Denied"

let string_of_notifications_result = function
  | Ok n -> "Ok " ^ string_of_notifications n
  | Error e -> "Error (" ^ Cap_error.to_string e ^ ")"

let check_notifications what expected actual =
  match
    String.equal
      (string_of_notifications_result expected)
      (string_of_notifications_result actual)
  with
  | true -> ()
  | false ->
      fail "%s: expected %s, got %s" what
        (string_of_notifications_result expected)
        (string_of_notifications_result actual)

let string_of_unit_result = function
  | Ok () -> "Ok ()"
  | Error e -> "Error (" ^ Cap_error.to_string e ^ ")"

let check_unit what expected actual =
  match
    String.equal (string_of_unit_result expected) (string_of_unit_result actual)
  with
  | true -> ()
  | false ->
      fail "%s: expected %s, got %s" what
        (string_of_unit_result expected)
        (string_of_unit_result actual)

let string_of_reason : Cap_foreground_run.reason -> string = function
  | User -> "User"
  | Timeout -> "Timeout"

(* ---------- notices ---------- *)

let notice ~title ?text ~value ~max ?action () : Cap_foreground_run.notice =
  {title; text; value; max; action}

(* ---------- start/update: the wire shape ---------- *)

let start_wire_shape () =
  clear_error ();
  set_start_json {|{"notifications":"granted"}|};
  let open Fut.Syntax in
  let* r1 =
    Cap_foreground_run.start
      (notice ~title:"T" ~value:3 ~max:101 ~action:"Interrompre" ())
  in
  check_call "start, no text" "start"
    [
      ("title", `String "T");
      ("value", `Int 3);
      ("max", `Int 101);
      ("action", `String "Interrompre");
    ];
  check_notifications "start resolves granted" (Ok Granted) r1;
  let+ r2 =
    Cap_foreground_run.start (notice ~title:"T2" ~text:"x" ~value:0 ~max:5 ())
  in
  check_call "start, no action" "start"
    [
      ("title", `String "T2");
      ("text", `String "x");
      ("value", `Int 0);
      ("max", `Int 5);
    ];
  check_notifications "start resolves granted (2)" (Ok Granted) r2

(* ---------- start: decoding [notifications] ---------- *)

let start_decodes_notifications () =
  let case what json expected =
    clear_error ();
    set_start_json json;
    let open Fut.Syntax in
    let+ r = Cap_foreground_run.start (notice ~title:"T" ~value:0 ~max:1 ()) in
    check_notifications what expected r
  in
  let open Fut.Syntax in
  let* () = case "denied" {|{"notifications":"denied"}|} (Ok Denied) in
  let* () =
    case "no notifications key" "{}"
      (Error (Cap_error.Unexpected "notifications"))
  in
  let* () =
    case "notifications = \"prompt\"" {|{"notifications":"prompt"}|}
      (Error (Cap_error.Unexpected "notifications"))
  in
  case "notifications = 1" {|{"notifications":1}|}
    (Error (Cap_error.Unexpected "notifications"))

(* ---------- rejections surface as Rejected ---------- *)

let rejections_surface_as_rejected () =
  set_error ~code:"START_NOT_ALLOWED" "m";
  let open Fut.Syntax in
  let* r1 = Cap_foreground_run.start (notice ~title:"T" ~value:0 ~max:1 ()) in
  check_notifications "start, plugin rejects"
    (Error (Cap_error.Rejected {code = Some "START_NOT_ALLOWED"; message = "m"}))
    r1;
  set_error ~code:"INVALID_ARGUMENT" "m";
  let* r2 = Cap_foreground_run.update (notice ~title:"T" ~value:0 ~max:1 ()) in
  check_unit "update, plugin rejects"
    (Error (Cap_error.Rejected {code = Some "INVALID_ARGUMENT"; message = "m"}))
    r2;
  set_error ~code:"E" "m";
  let* r3 = Cap_foreground_run.stop () in
  check_unit "stop, plugin rejects"
    (Error (Cap_error.Rejected {code = Some "E"; message = "m"}))
    r3;
  let+ r4 = Cap_foreground_run.on_interrupt (fun _ -> ()) in
  clear_error ();
  match r4 with
  | Error (Cap_error.Rejected {code = Some "E"; message = "m"}) -> ()
  | Error e ->
      fail "on_interrupt, plugin rejects: expected Rejected E, got %s"
        (Cap_error.to_string e)
  | Ok _ -> fail "on_interrupt, plugin rejects: expected Error, got Ok"

(* ---------- update / stop ---------- *)

let update_and_stop () =
  clear_error ();
  let open Fut.Syntax in
  let* r1 =
    Cap_foreground_run.update
      (notice ~title:"U" ~value:7 ~max:10 ~action:"Interrompre" ())
  in
  check_call "update, no text" "update"
    [
      ("title", `String "U");
      ("value", `Int 7);
      ("max", `Int 10);
      ("action", `String "Interrompre");
    ];
  check_unit "update resolves" (Ok ()) r1;
  let+ r2 = Cap_foreground_run.stop () in
  check_call "stop, no arguments" "stop" [];
  check_unit "stop resolves" (Ok ()) r2

(* ---------- "interrupt" listener ---------- *)

let on_interrupt_decodes_reason () =
  clear_error ();
  let open Fut.Syntax in
  let received = ref [] in
  let* r =
    Cap_foreground_run.on_interrupt (fun reason ->
        received := reason :: !received)
  in
  let listener =
    match r with
    | Error e ->
        fail "on_interrupt: expected Ok, got Error (%s)" (Cap_error.to_string e);
        None
    | Ok l -> Some l
  in
  (match String.equal (listener_name ()) "interrupt" with
  | true -> ()
  | false ->
      fail "on_interrupt: registered on %S, expected \"interrupt\""
        (listener_name ()));
  List.iter fire
    [
      {|{"reason":"user"}|};
      {|{"reason":"timeout"}|};
      "{}";
      {|{"reason":"x"}|};
      {|{"reason":3}|};
    ];
  let got = List.rev_map string_of_reason !received in
  let expected = List.map string_of_reason [User; Timeout; User; User; User] in
  (match List.equal String.equal got expected with
  | true -> ()
  | false ->
      fail "on_interrupt: expected [%s], got [%s]"
        (String.concat "; " expected)
        (String.concat "; " got));
  match listener with
  | None -> Fut.return ()
  | Some l -> (
      let+ r = Cap_foreground_run.remove l in
      check_unit "remove resolves" (Ok ()) r;
      let before = List.length !received in
      fire {|{"reason":"user"}|};
      match List.length !received = before with
      | true -> ()
      | false -> fail "remove: the listener still receives events")

(* ---------- plugin absent ---------- *)

let plugin_absent () =
  clear_error ();
  empty_plugin_table ();
  let open Fut.Syntax in
  let* r1 = Cap_foreground_run.start (notice ~title:"T" ~value:0 ~max:1 ()) in
  check_notifications "start, plugin absent"
    (Error (Cap_error.Unavailable "foregroundRun")) r1;
  let* r2 = Cap_foreground_run.update (notice ~title:"T" ~value:0 ~max:1 ()) in
  check_unit "update, plugin absent"
    (Error (Cap_error.Unavailable "foregroundRun")) r2;
  let* r3 = Cap_foreground_run.stop () in
  check_unit "stop, plugin absent"
    (Error (Cap_error.Unavailable "foregroundRun")) r3;
  let+ r4 = Cap_foreground_run.on_interrupt (fun _ -> ()) in
  match r4 with
  | Error (Cap_error.Unavailable "foregroundRun") -> ()
  | Error e ->
      fail "on_interrupt, plugin absent: expected Unavailable, got %s"
        (Cap_error.to_string e)
  | Ok _ -> fail "on_interrupt, plugin absent: expected Error, got Ok"

let () =
  set_exit_code 1;
  let open Fut.Syntax in
  let all =
    let* () = start_wire_shape () in
    let* () = start_decodes_notifications () in
    let* () = rejections_surface_as_rejected () in
    let* () = update_and_stop () in
    let* () = on_interrupt_decodes_reason () in
    (* last: it empties globalThis.herbier for good. *)
    plugin_absent ()
  in
  Fut.await all (fun () -> set_exit_code 0)
