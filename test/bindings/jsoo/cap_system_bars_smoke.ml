(* Herbier_bindings.Cap_system_bars, under node, over the stub plugin of
   system_bars_stub.js (preloaded by test/bindings/jsoo/dune): the exact wire
   shape set_style sends for each bar/style pair, its two rejection paths
   (promise reject, synchronous throw) and the plugin-absent case. Silent on
   success; the first mismatch goes to stderr and exits 1 (smoke.ml's own
   pattern: process.exit leaves no room for a later future to overwrite the
   failure). *)

module Cap_system_bars = Herbier_bindings.Cap_system_bars
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

let clear_calls () = Jv.set Jv.global "__calls_json" (Jv.of_string "[]")
let clear_reject () = Jv.set Jv.global "__next_reject" Jv.null

let set_reject ?code message =
  let fields =
    ("message", Jv.of_string message)
    :: (match code with None -> [] | Some c -> [("code", Jv.of_string c)])
  in
  Jv.set Jv.global "__next_reject" (Jv.obj (Array.of_list fields))

let set_throw () = Jv.set Jv.global "__next_throw" (Jv.of_bool true)
let empty_plugin_table () = Jv.set Jv.global "herbier" (Jv.obj [||])

(* The stub's recorded setStyle calls, in order. *)
let calls () =
  match
    Yojson.Safe.from_string (Jv.to_string (Jv.get Jv.global "__calls_json"))
  with
  | `List l -> l
  | j ->
      fail "unexpected __calls_json: %s" (Yojson.Safe.to_string j);
      []

(* ---------- rendering (diagnostics and equality both) ---------- *)

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

(* [actual] carries exactly the keys of [expected] (same string values), no
   more, no fewer. *)
let check_call what expected actual =
  match actual with
  | `Assoc fields ->
      let sorted l = List.sort compare l in
      let actual_keys = sorted (List.map fst fields) in
      let expected_keys = sorted (List.map fst expected) in
      (match List.equal String.equal actual_keys expected_keys with
      | true -> ()
      | false ->
          fail "%s: expected keys %s, got %s" what
            (String.concat "," expected_keys)
            (String.concat "," actual_keys));
      List.iter
        (fun (k, v) ->
          match List.assoc_opt k fields with
          | Some (`String s) when String.equal s v -> ()
          | Some other ->
              fail "%s: field %s expected %S, got %s" what k v
                (Yojson.Safe.to_string other)
          | None -> fail "%s: field %s missing" what k)
        expected
  | j -> fail "%s: expected an object, got %s" what (Yojson.Safe.to_string j)

let last_call what =
  match List.rev (calls ()) with
  | c :: _ -> c
  | [] ->
      fail "%s: no call recorded" what;
      `Null

(* ---------- set_style: the wire shape ---------- *)

let set_style_light_status () =
  clear_calls ();
  clear_reject ();
  let open Fut.Syntax in
  let+ r =
    Cap_system_bars.set_style ~bar:Cap_system_bars.Status_bar
      ~style:Cap_system_bars.Light
  in
  check_unit "set_style (Status_bar, Light)" (Ok ()) r;
  check_call "set_style (Status_bar, Light) wire shape"
    [("style", "LIGHT"); ("bar", "StatusBar")]
    (last_call "set_style (Status_bar, Light)")

let set_style_dark_navigation () =
  clear_calls ();
  clear_reject ();
  let open Fut.Syntax in
  let+ r =
    Cap_system_bars.set_style ~bar:Cap_system_bars.Navigation_bar
      ~style:Cap_system_bars.Dark
  in
  check_unit "set_style (Navigation_bar, Dark)" (Ok ()) r;
  check_call "set_style (Navigation_bar, Dark) wire shape"
    [("style", "DARK"); ("bar", "NavigationBar")]
    (last_call "set_style (Navigation_bar, Dark)")

(* ---------- rejection paths ---------- *)

let rejected_promise_surfaces_as_rejected () =
  clear_calls ();
  set_reject ~code:"UNIMPLEMENTED" "not implemented";
  let open Fut.Syntax in
  let+ r =
    Cap_system_bars.set_style ~bar:Cap_system_bars.Status_bar
      ~style:Cap_system_bars.Light
  in
  check_unit "set_style, plugin rejects"
    (Error
       (Cap_error.Rejected
          {code = Some "UNIMPLEMENTED"; message = "not implemented"}))
    r;
  check_call "set_style, plugin rejects: wire shape"
    [("style", "LIGHT"); ("bar", "StatusBar")]
    (last_call "set_style, plugin rejects")

let synchronous_throw_surfaces_as_rejected () =
  clear_calls ();
  clear_reject ();
  set_throw ();
  let open Fut.Syntax in
  let+ r =
    Cap_system_bars.set_style ~bar:Cap_system_bars.Status_bar
      ~style:Cap_system_bars.Dark
  in
  (match r with
  | Error (Cap_error.Rejected _) -> ()
  | other ->
      fail "set_style, synchronous throw: expected Error (Rejected _), got %s"
        (string_of_unit_result other));
  check_call "set_style, synchronous throw: wire shape"
    [("style", "DARK"); ("bar", "StatusBar")]
    (last_call "set_style, synchronous throw")

(* ---------- plugin absent ---------- *)

let plugin_absent () =
  clear_calls ();
  clear_reject ();
  empty_plugin_table ();
  let open Fut.Syntax in
  let+ r =
    Cap_system_bars.set_style ~bar:Cap_system_bars.Status_bar
      ~style:Cap_system_bars.Light
  in
  check_unit "set_style, plugin absent"
    (Error (Cap_error.Unavailable "systemBars")) r;
  match calls () with
  | [] -> ()
  | _ -> fail "set_style, plugin absent: a call was recorded"

let () =
  set_exit_code 1;
  let open Fut.Syntax in
  let all =
    let* () = set_style_light_status () in
    let* () = set_style_dark_navigation () in
    let* () = rejected_promise_surfaces_as_rejected () in
    let* () = synchronous_throw_surfaces_as_rejected () in
    (* last: it empties globalThis.herbier for good. *)
    plugin_absent ()
  in
  Fut.await all (fun () -> set_exit_code 0)
