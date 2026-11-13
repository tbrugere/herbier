(* Fut_result.traverse under node: the order in which the items start and
   settle, the stop at the first Error and the Ok order are the same as the
   two folds it replaced, copied below verbatim. Silent on success; the first
   mismatch goes to stderr and exits 1. The exit code stays 1 until every
   case has run, so a future that never resolves fails the run. *)

module Fut_result = Herbier_bindings.Fut_result

let process = Jv.get Jv.global "process"
let set_exit_code n = Jv.set process "exitCode" (Jv.of_int n)

let fail fmt =
  Printf.ksprintf
    (fun m ->
      prerr_endline m;
      Jv.call process "exit" [|Jv.of_int 1|] |> ignore)
    fmt

(* photos_io/capture.ml's pick, before Fut_result. *)
let capture_fold picked media =
  let open Fut.Result_syntax in
  List.fold_left
    (fun acc m ->
      let* shots = acc in
      let* s = picked m in
      Fut.ok (s :: shots))
    (Fut.ok []) media
  |> Fut.map (Result.map List.rev)

(* refs_io/organ_thumbs.ml's each, before Fut_result. *)
let organ_each items f =
  List.fold_left
    (fun acc x ->
      Fut.bind acc (function
        | Error e -> Fut.return (Error e)
        | Ok done_ -> Fut.map (Result.map (fun r -> (x, r) :: done_)) (f x)))
    (Fut.ok []) items
  |> Fut.map (Result.map List.rev)

let organ_each_new items f =
  Fut_result.traverse
    (fun x -> Fut.map (Result.map (fun r -> (x, r))) (f x))
    items

(* Each item starts, waits a timer tick, then settles: [Error] on [bad]. *)
let item log ~bad x =
  log := Printf.sprintf "start %d" x :: !log;
  let fut, set = Fut.create () in
  let _ : Brr.G.timer_id =
    Brr.G.set_timeout ~ms:(5 - x) (fun () ->
        log := Printf.sprintf "end %d" x :: !log;
        set (match x = bad with true -> Error x | false -> Ok (x * 10)))
  in
  fut

let show = function
  | Ok l -> "Ok [" ^ String.concat ";" (List.map string_of_int l) ^ "]"
  | Error e -> Printf.sprintf "Error %d" e

let run name ~bad items run_with =
  let log = ref [] in
  let fut = run_with (item log ~bad) items in
  log := "returned" :: !log;
  Fut.map (fun r -> (name, show r, List.rev !log)) fut

let same case (n1, r1, l1) (n2, r2, l2) =
  match String.equal r1 r2 && List.equal String.equal l1 l2 with
  | true -> ()
  | false ->
      fail "%s: %s gave %s [%s], %s gave %s [%s]" case n1 r1
        (String.concat ", " l1) n2 r2 (String.concat ", " l2)

let expect case (_, r, l) (r', l') =
  match String.equal r r' && List.equal String.equal l l' with
  | true -> ()
  | false -> fail "%s: got %s [%s]" case r (String.concat ", " l)

let pairs f items = Fut.map (Result.map (List.map snd)) (f items)

let case name ~bad items expected =
  let open Fut.Syntax in
  let* traverse = run "traverse" ~bad items Fut_result.traverse in
  let* capture = run "capture fold" ~bad items capture_fold in
  let* each =
    run "organ each" ~bad items (fun f items ->
        pairs (fun items -> organ_each items f) items)
  in
  let+ each_new =
    run "organ each on traverse" ~bad items (fun f items ->
        pairs (fun items -> organ_each_new items f) items)
  in
  same name traverse capture;
  same name traverse each;
  same name each each_new;
  expect name traverse expected

let () =
  set_exit_code 1;
  let open Fut.Syntax in
  let all =
    let* () =
      case "all Ok" ~bad:0 [1; 2; 3]
        ( "Ok [10;20;30]",
          [
            "returned";
            "start 1";
            "end 1";
            "start 2";
            "end 2";
            "start 3";
            "end 3";
          ] )
    in
    let* () =
      case "stops at the first Error" ~bad:2 [1; 2; 3; 4]
        ("Error 2", ["returned"; "start 1"; "end 1"; "start 2"; "end 2"])
    in
    case "empty" ~bad:0 [] ("Ok []", ["returned"])
  in
  Fut.await all (fun () -> set_exit_code 0)
