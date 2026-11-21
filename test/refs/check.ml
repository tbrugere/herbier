(* Testables and helpers shared by the decoder tests. *)

module Decode = Herbier_refs.Decode
module Qid = Herbier_refs.Qid
module Request = Herbier_refs.Request
module Source = Herbier_domain.Reference.Source
module Fixture = Herbier_test_support.Fixture
module Testable = Herbier_test_support.Testable
module Text = Herbier_test_support.Text

let error =
  Alcotest.testable
    (fun f e -> Format.pp_print_string f (Decode.error_to_string e))
    Decode.equal_error

let check_result name value expected actual =
  Alcotest.(check (result value error)) name expected actual

let check_unexpected_path name expected_path = function
  | Error (Decode.Unexpected {path; _}) ->
      Alcotest.(check string) name expected_path path
  | Error e ->
      Alcotest.failf "%s: expected Unexpected, got %s" name
        (Decode.error_to_string e)
  | Ok _ -> Alcotest.failf "%s: expected Error, got Ok" name

let opt f = function None -> `Null | Some v -> f v

let some_qid name s =
  match Qid.of_string s with
  | Some q -> q
  | None -> Alcotest.failf "%s: bad qid literal %S" name s

(* A recorded payload, parsed. Raised at module initialisation, the failure
   names the fixture and the parse error. *)
let json name =
  match Decode.json_of_string (Fixture.read name) with
  | Ok json -> json
  | Error e -> failwith (name ^ ": " ^ Decode.error_to_string e)

(* ---------- recording script consistency ---------- *)

let script_path = "../../scripts/record-refs-fixtures.sh"

let read_script () =
  try Some (In_channel.with_open_bin script_path In_channel.input_all)
  with Sys_error _ -> None

(* [check_recorded file request] checks that [file]'s [fetch] (or
   [fetch_absent] when [~absent:true]) line in scripts/record-refs-fixtures.sh
   is exactly the source and URL [request] builds. *)
let check_recorded ?(absent = false) file (request : Request.t) =
  let tag = match absent with true -> "fetch_absent" | false -> "fetch" in
  let line =
    Printf.sprintf "%s %s %s \"%s\"" tag file
      (Source.to_string request.source)
      request.url
  in
  match read_script () with
  | None ->
      Alcotest.fail
        "scripts/record-refs-fixtures.sh is missing: cannot check the fixture \
         URL against it"
  | Some script -> (
      match Text.contains ~sub:line script with
      | true -> ()
      | false ->
          Alcotest.failf "%s: line %s not found in %s" file line script_path)

let check_fixture_exists file =
  match Fixture.exists file with
  | true -> ()
  | false -> Alcotest.failf "missing fixture test/fixtures/%s" file
