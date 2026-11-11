(* Testables and helpers shared by the decoder tests. *)

module Decode = Herbier_refs.Decode
module Qid = Herbier_refs.Qid

let yojson =
  Alcotest.testable
    (fun f j -> Format.pp_print_string f (Yojson.Safe.pretty_to_string j))
    Yojson.Safe.equal

let error =
  Alcotest.testable
    (fun f e -> Format.pp_print_string f (Decode.error_to_string e))
    Decode.equal_error

let check_result name ~to_json expected actual =
  Alcotest.(check (result yojson error))
    name
    (Result.map to_json expected)
    (Result.map to_json actual)

let opt f = function None -> `Null | Some v -> f v

let some_qid name s =
  match Qid.of_string s with
  | Some q -> q
  | None -> Alcotest.failf "%s: bad qid literal %S" name s

let starts_with ~prefix s =
  String.length s >= String.length prefix
  && String.equal (String.sub s 0 (String.length prefix)) prefix

let contains ~needle haystack =
  let n = String.length needle and h = String.length haystack in
  let rec at i =
    match i > h - n with
    | true -> false
    | false -> (
        match String.equal (String.sub haystack i n) needle with
        | true -> true
        | false -> at (i + 1))
  in
  match n with 0 -> true | _ -> at 0

(* A recorded payload, parsed. Raised at module initialisation, the failure
   names the fixture and the parse error. *)
let json name =
  match Decode.json_of_string (Fixture.read name) with
  | Ok json -> json
  | Error e -> failwith (name ^ ": " ^ Decode.error_to_string e)
