(* Herbier_bindings.Cap_uploader (app/bindings/cap_uploader.mli), under node,
   over the stub plugin of uploader_stub.js (preloaded by
   test/bindings/jsoo/dune): the wire shape enqueue sends, jobs' decoding of
   every wire state and its error paths, and the plugin-absent case. Silent
   on success; the first mismatch goes to stderr and exits 1 (smoke.ml's own
   pattern: process.exit leaves no room for a later future to overwrite the
   failure). *)

module Cap_uploader = Herbier_bindings.Cap_uploader
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

let set_jobs_json s = Jv.set Jv.global "__next_jobs_json" (Jv.of_string s)
let clear_error () = Jv.set Jv.global "__next_error" Jv.null

let set_error ?code message =
  let fields =
    ("message", Jv.of_string message)
    :: (match code with None -> [] | Some c -> [("code", Jv.of_string c)])
  in
  Jv.set Jv.global "__next_error" (Jv.obj (Array.of_list fields))

let empty_plugin_table () = Jv.set Jv.global "herbier" (Jv.obj [||])

(* The stub's last call, as JSON.stringify([name, args]) recorded it. *)
let last_call () =
  match
    Yojson.Safe.from_string (Jv.to_string (Jv.get Jv.global "__last_call_json"))
  with
  | `List [`String name; `Assoc fields] -> (name, fields)
  | j ->
      fail "unexpected __last_call_json: %s" (Yojson.Safe.to_string j);
      ("", [])

let str_field fields k =
  match List.assoc_opt k fields with
  | Some (`String s) -> s
  | _ -> Printf.sprintf "<%s missing>" k

let check_eq what expected actual =
  match String.equal expected actual with
  | true -> ()
  | false -> fail "%s: expected %S, got %S" what expected actual

(* ---------- rendering (diagnostics and equality both) ---------- *)

let string_of_failure : Cap_uploader.failure -> string = function
  | Answered {status; body} ->
      Printf.sprintf "Answered {status=%d; body=%S}" status body
  | File_missing -> "File_missing"
  | Gave_up m -> Printf.sprintf "Gave_up %S" m

let string_of_state : Cap_uploader.state -> string = function
  | Enqueued -> "Enqueued"
  | Blocked -> "Blocked"
  | Running -> "Running"
  | Succeeded {status; body} ->
      Printf.sprintf "Succeeded {status=%d; body=%S}" status body
  | Failed f -> "Failed (" ^ string_of_failure f ^ ")"
  | Cancelled -> "Cancelled"

let string_of_job (j : Cap_uploader.job) =
  Printf.sprintf "{id=%S; state=%s; attempts=%d}" j.id (string_of_state j.state)
    j.attempts

let string_of_jobs_result = function
  | Ok jobs -> "Ok [" ^ String.concat "; " (List.map string_of_job jobs) ^ "]"
  | Error e -> "Error (" ^ Cap_error.to_string e ^ ")"

let check_jobs what expected actual =
  match
    String.equal (string_of_jobs_result expected) (string_of_jobs_result actual)
  with
  | true -> ()
  | false ->
      fail "%s: expected %s, got %s" what
        (string_of_jobs_result expected)
        (string_of_jobs_result actual)

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

(* ---------- enqueue: the wire shape ---------- *)

let enqueue_wire_shape () =
  clear_error ();
  let open Fut.Syntax in
  let* r1 =
    Cap_uploader.enqueue ~id:"a" ~path:"originals/a"
      ~url:"https://example.test/u" ~mime:"image/jpeg"
      ~network:Cap_uploader.Unmetered
  in
  check_unit "enqueue (unmetered)" (Ok ()) r1;
  let name, fields = last_call () in
  check_eq "call name" "enqueue" name;
  check_eq "id" "a" (str_field fields "id");
  check_eq "path" "originals/a" (str_field fields "path");
  check_eq "url" "https://example.test/u" (str_field fields "url");
  check_eq "mimeType" "image/jpeg" (str_field fields "mimeType");
  check_eq "network (Unmetered)" "unmetered" (str_field fields "network");
  let+ r2 =
    Cap_uploader.enqueue ~id:"b" ~path:"originals/b"
      ~url:"https://example.test/v" ~mime:"image/png" ~network:Cap_uploader.Any
  in
  check_unit "enqueue (any)" (Ok ()) r2;
  let _, fields2 = last_call () in
  check_eq "network (Any)" "connected" (str_field fields2 "network")

(* ---------- jobs: decoding ---------- *)

let jobs_decode_all_wire_states () =
  clear_error ();
  set_jobs_json
    (Yojson.Safe.to_string
       (`Assoc
          [
            ( "jobs",
              `List
                [
                  `Assoc
                    [
                      ("id", `String "j1");
                      ("state", `String "ENQUEUED");
                      ("attempts", `Int 0);
                    ];
                  `Assoc
                    [
                      ("id", `String "j2");
                      ("state", `String "BLOCKED");
                      ("attempts", `Int 1);
                    ];
                  `Assoc
                    [
                      ("id", `String "j3");
                      ("state", `String "RUNNING");
                      ("attempts", `Int 2);
                    ];
                  `Assoc
                    [
                      ("id", `String "j4");
                      ("state", `String "SUCCEEDED");
                      ("attempts", `Int 3);
                      ("httpStatus", `Int 200);
                      ("body", `String {|{"id":"f"}|});
                    ];
                  `Assoc
                    [
                      ("id", `String "j5");
                      ("state", `String "FAILED");
                      ("attempts", `Int 4);
                      ("httpStatus", `Int 404);
                      ("body", `String "Not Found");
                    ];
                  `Assoc
                    [
                      ("id", `String "j6");
                      ("state", `String "CANCELLED");
                      ("attempts", `Int 5);
                    ];
                ] );
          ]));
  let open Fut.Syntax in
  let+ r = Cap_uploader.jobs () in
  let expected : Cap_uploader.job list =
    [
      {id = "j1"; state = Enqueued; attempts = 0};
      {id = "j2"; state = Blocked; attempts = 1};
      {id = "j3"; state = Running; attempts = 2};
      {
        id = "j4";
        state = Succeeded {status = 200; body = {|{"id":"f"}|}};
        attempts = 3;
      };
      {
        id = "j5";
        state = Failed (Answered {status = 404; body = "Not Found"});
        attempts = 4;
      };
      {id = "j6"; state = Cancelled; attempts = 5};
    ]
  in
  check_jobs "jobs (one entry per wire state)" (Ok expected) r

let jobs_failed_404_no_body () =
  clear_error ();
  set_jobs_json
    {|{"jobs":[{"id":"j1","state":"FAILED","attempts":0,"httpStatus":404}]}|};
  let open Fut.Syntax in
  let+ r = Cap_uploader.jobs () in
  check_jobs "jobs (FAILED 404, no body)"
    (Ok
       [
         {
           id = "j1";
           state = Failed (Answered {status = 404; body = ""});
           attempts = 0;
         };
       ])
    r

(* The FAILED entries without httpStatus, keyed as UploadWorker.java's ERROR
   and MESSAGE and copied by UploaderPlugin.entry. *)
let failed_entry ?error ?message () =
  `Assoc
    ([("id", `String "j1"); ("state", `String "FAILED"); ("attempts", `Int 9)]
    @ (match error with None -> [] | Some e -> [("error", `String e)])
    @ match message with None -> [] | Some m -> [("message", `String m)])

let jobs_failed_without_status () =
  let case what entry expected =
    clear_error ();
    set_jobs_json (Yojson.Safe.to_string (`Assoc [("jobs", `List [entry])]));
    let open Fut.Syntax in
    let+ r = Cap_uploader.jobs () in
    check_jobs what (Ok [{id = "j1"; state = Failed expected; attempts = 9}]) r
  in
  let open Fut.Syntax in
  let* () =
    case "jobs (FAILED FILE_NOT_FOUND)"
      (failed_entry ~error:"FILE_NOT_FOUND" ())
      File_missing
  in
  let* () =
    case "jobs (FAILED GAVE_UP with a message)"
      (failed_entry ~error:"GAVE_UP" ~message:"HTTP 503" ())
      (Gave_up "HTTP 503")
  in
  let* () =
    case "jobs (FAILED GAVE_UP without a message)"
      (failed_entry ~error:"GAVE_UP" ())
      (Gave_up "")
  in
  let* () =
    case "jobs (FAILED, unknown error)"
      (failed_entry ~error:"WEIRD" ())
      (Gave_up "")
  in
  case "jobs (FAILED, empty output)" (failed_entry ()) (Gave_up "")

let jobs_unknown_state_is_unexpected () =
  clear_error ();
  set_jobs_json {|{"jobs":[{"id":"j1","state":"WEIRD","attempts":0}]}|};
  let open Fut.Syntax in
  let+ r = Cap_uploader.jobs () in
  check_jobs "jobs (unknown state)" (Error (Cap_error.Unexpected "state")) r

let jobs_succeeded_without_body_is_unexpected () =
  clear_error ();
  set_jobs_json
    {|{"jobs":[{"id":"j1","state":"SUCCEEDED","attempts":0,"httpStatus":200}]}|};
  let open Fut.Syntax in
  let+ r = Cap_uploader.jobs () in
  check_jobs "jobs (SUCCEEDED without body)"
    (Error (Cap_error.Unexpected "body")) r

let jobs_no_jobs_key_is_unexpected () =
  clear_error ();
  set_jobs_json "{}";
  let open Fut.Syntax in
  let+ r = Cap_uploader.jobs () in
  check_jobs "jobs (no jobs key)" (Error (Cap_error.Unexpected "jobs")) r

let jobs_rejected_promise_surfaces_as_rejected () =
  set_error ~code:"UNAVAILABLE" "boom";
  let open Fut.Syntax in
  let+ r = Cap_uploader.jobs () in
  check_jobs "jobs (plugin rejects)"
    (Error (Cap_error.Rejected {code = Some "UNAVAILABLE"; message = "boom"}))
    r

(* ---------- plugin absent ---------- *)

let plugin_absent () =
  clear_error ();
  empty_plugin_table ();
  let open Fut.Syntax in
  let* r1 =
    Cap_uploader.enqueue ~id:"a" ~path:"originals/a"
      ~url:"https://example.test/u" ~mime:"image/jpeg" ~network:Cap_uploader.Any
  in
  check_unit "enqueue, plugin absent" (Error (Cap_error.Unavailable "uploader"))
    r1;
  let* r2 = Cap_uploader.jobs () in
  check_jobs "jobs, plugin absent" (Error (Cap_error.Unavailable "uploader")) r2;
  let+ r3 = Cap_uploader.cancel ~id:"a" in
  check_unit "cancel, plugin absent" (Error (Cap_error.Unavailable "uploader"))
    r3

let () =
  set_exit_code 1;
  let open Fut.Syntax in
  let all =
    let* () = enqueue_wire_shape () in
    let* () = jobs_decode_all_wire_states () in
    let* () = jobs_failed_404_no_body () in
    let* () = jobs_failed_without_status () in
    let* () = jobs_unknown_state_is_unexpected () in
    let* () = jobs_succeeded_without_body_is_unexpected () in
    let* () = jobs_no_jobs_key_is_unexpected () in
    let* () = jobs_rejected_promise_surfaces_as_rejected () in
    (* last: it empties globalThis.herbier for good. *)
    plugin_absent ()
  in
  Fut.await all (fun () -> set_exit_code 0)
