(* Herbier_bindings.Cap_volume_key (app/bindings/cap_volume_key.mli), under
   node, over the stub plugin of volume_key_stub.js (preloaded by
   test/bindings/jsoo/dune): enable/disable reach the plugin, rejections
   surface as [Rejected], the ["volumeDown"] listener calls [f] once per event
   and stops after its removal, and the plugin-absent case. Silent on success;
   the first mismatch goes to stderr and exits 1. *)

module Cap_volume_key = Herbier_bindings.Cap_volume_key
module Cap_error = Herbier_bindings.Cap_error

let process = Jv.get Jv.global "process"
let set_exit_code n = Jv.set process "exitCode" (Jv.of_int n)

let fail fmt =
  Printf.ksprintf
    (fun m ->
      prerr_endline m;
      Jv.call process "exit" [|Jv.of_int 1|] |> ignore)
    fmt

let clear_error () = Jv.set Jv.global "__next_error" Jv.null

let set_error ~code message =
  Jv.set Jv.global "__next_error"
    (Jv.obj [|("code", Jv.of_string code); ("message", Jv.of_string message)|])

let last_call () = Jv.to_string (Jv.get Jv.global "__last_call")
let listener_name () = Jv.to_string (Jv.get Jv.global "__listener_name")
let fire () = Jv.call Jv.global "__fire" [||] |> ignore

let string_of_unit_result = function
  | Ok () -> "Ok ()"
  | Error e -> "Error (" ^ Cap_error.to_string e ^ ")"

let check_unit what expected actual =
  let e = string_of_unit_result expected and a = string_of_unit_result actual in
  match String.equal e a with
  | true -> ()
  | false -> fail "%s: expected %s, got %s" what e a

let check_call what expected =
  match String.equal expected (last_call ()) with
  | true -> ()
  | false -> fail "%s: expected call %S, got %S" what expected (last_call ())

let enable_disable () =
  clear_error ();
  let open Fut.Syntax in
  let* r1 = Cap_volume_key.enable () in
  check_call "enable" "enable";
  check_unit "enable resolves" (Ok ()) r1;
  let* r2 = Cap_volume_key.disable () in
  check_call "disable" "disable";
  check_unit "disable resolves" (Ok ()) r2;
  set_error ~code:"E" "m";
  let rejected = Error (Cap_error.Rejected {code = Some "E"; message = "m"}) in
  let* r3 = Cap_volume_key.enable () in
  check_unit "enable, plugin rejects" rejected r3;
  let+ r4 = Cap_volume_key.disable () in
  check_unit "disable, plugin rejects" rejected r4;
  clear_error ()

let listener () =
  let open Fut.Syntax in
  set_error ~code:"E" "m";
  let* r0 = Cap_volume_key.on_volume_down (fun () -> ()) in
  (match r0 with
  | Error (Cap_error.Rejected {code = Some "E"; message = "m"}) -> ()
  | Error e -> fail "on_volume_down rejects: got %s" (Cap_error.to_string e)
  | Ok _ -> fail "on_volume_down rejects: got Ok");
  clear_error ();
  let presses = ref 0 in
  let* r = Cap_volume_key.on_volume_down (fun () -> incr presses) in
  match r with
  | Error e ->
      fail "on_volume_down: expected Ok, got %s" (Cap_error.to_string e);
      Fut.return ()
  | Ok l -> (
      (match String.equal (listener_name ()) "volumeDown" with
      | true -> ()
      | false -> fail "registered on %S, expected volumeDown" (listener_name ()));
      fire ();
      fire ();
      (match !presses with
      | 2 -> ()
      | n -> fail "on_volume_down: expected 2 calls, got %d" n);
      let+ r = Cap_volume_key.remove l in
      check_unit "remove resolves" (Ok ()) r;
      fire ();
      match !presses with
      | 2 -> ()
      | _ -> fail "remove: the listener still receives events")

let plugin_absent () =
  Jv.set Jv.global "herbier" (Jv.obj [||]);
  let open Fut.Syntax in
  let absent = Error (Cap_error.Unavailable "volumeKey") in
  let* r1 = Cap_volume_key.enable () in
  check_unit "enable, plugin absent" absent r1;
  let* r2 = Cap_volume_key.disable () in
  check_unit "disable, plugin absent" absent r2;
  let+ r3 = Cap_volume_key.on_volume_down (fun () -> ()) in
  match r3 with
  | Error (Cap_error.Unavailable "volumeKey") -> ()
  | Error e -> fail "on_volume_down, absent: got %s" (Cap_error.to_string e)
  | Ok _ -> fail "on_volume_down, absent: got Ok"

let () =
  set_exit_code 1;
  let open Fut.Syntax in
  let all =
    let* () = enable_disable () in
    let* () = listener () in
    (* last: it empties globalThis.herbier for good. *)
    plugin_absent ()
  in
  Fut.await all (fun () -> set_exit_code 0)
