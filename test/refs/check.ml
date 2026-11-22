(* Testables and helpers shared by the decoder tests. *)

module Decode = Herbier_refs.Decode
module Qid = Herbier_refs.Qid
module Request = Herbier_refs.Request
module Source = Herbier_domain.Reference.Source
module Fixture = Herbier_test_support.Fixture
module Testable = Herbier_test_support.Testable
module Text = Herbier_test_support.Text
module Json = Herbier_net.Json

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

(* ---------- MediaWiki / TextExtracts recorded answers ---------- *)

(* [query.pages[0]] of a recorded [action=query] answer (Plantuse's revisions,
   Wikipedia's extracts), the shape [Sources.Plantuse]/[Sources.Wikipedia]
   decode; [None] when the answer has no such path (an [error] object, an
   empty [pages] array). *)
let first_page json =
  match Json.member "query" json with
  | None -> None
  | Some q -> (
      match Json.member "pages" q with
      | Some (`List (p :: _)) -> Some p
      | _ -> None)

(* The wikitext of a recorded Plantuse [page] fixture's first page
   ([revisions.[0].slots.main.content]). *)
let wikitext_of_fixture file =
  match first_page (json file) with
  | None -> Alcotest.failf "%s: no query.pages[0]" file
  | Some p -> (
      match Json.member "revisions" p with
      | Some (`List (rev :: _)) -> (
          match Json.member "slots" rev with
          | Some slots -> (
              match Json.member "main" slots with
              | Some main -> (
                  match Json.string_member "content" main with
                  | Some s -> s
                  | None -> Alcotest.failf "%s: no content" file)
              | None -> Alcotest.failf "%s: no main slot" file)
          | None -> Alcotest.failf "%s: no slots" file)
      | _ -> Alcotest.failf "%s: no revisions[0]" file)

(* The plain-text [extract] of a recorded Wikipedia TextExtracts fixture's
   first page. *)
let extract_of_fixture file =
  match first_page (json file) with
  | None -> Alcotest.failf "%s: no query.pages[0]" file
  | Some p -> (
      match Json.string_member "extract" p with
      | Some s -> s
      | None -> Alcotest.failf "%s: no extract" file)
