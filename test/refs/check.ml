(* Testables and helpers shared by the decoder tests. *)

module Decode = Herbier_refs.Decode
module Qid = Herbier_refs.Qid
module Fixture = Herbier_test_support.Fixture
module Testable = Herbier_test_support.Testable

let error =
  Alcotest.testable
    (fun f e -> Format.pp_print_string f (Decode.error_to_string e))
    Decode.equal_error

let check_result name value expected actual =
  Alcotest.(check (result value error)) name expected actual

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
