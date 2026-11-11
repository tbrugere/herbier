type error =
  | Not_json of string
  | Unexpected of {path : string; expected : string}
  | Api_error of {code : string; info : string}

let error_to_string = function
  | Not_json msg -> "not JSON: " ^ msg
  | Unexpected {path; expected} ->
      Printf.sprintf "unexpected payload at %S: expected %s" path expected
  | Api_error {code; info} -> Printf.sprintf "API error %s: %s" code info

let equal_error a b =
  match (a, b) with
  | Not_json a, Not_json b -> String.equal a b
  | Unexpected a, Unexpected b ->
      String.equal a.path b.path && String.equal a.expected b.expected
  | Api_error a, Api_error b ->
      String.equal a.code b.code && String.equal a.info b.info
  | (Not_json _ | Unexpected _ | Api_error _), _ -> false

let json_of_string s =
  match Yojson.Safe.from_string s with
  | json -> Ok json
  (* Malformed text raises Json_error; under js_of_ocaml a deeply nested
     body raises Failure (a JS stack overflow) instead. Whatever the
     exception, the body degrades to Not_json (style §8.4). *)
  | exception Yojson.Json_error msg -> Error (Not_json msg)
  | exception e -> Error (Not_json (Printexc.to_string e))

let member name = function
  | `Assoc fields -> (
      match List.assoc_opt name fields with
      | None | Some `Null -> None
      | Some v -> Some v)
  | _ -> None

let non_blank s = match String.trim s with "" -> None | _ -> Some s

let is_digits s =
  s <> "" && String.for_all (function '0' .. '9' -> true | _ -> false) s

let string name json =
  match member name json with Some (`String s) -> non_blank s | _ -> None

let int name json =
  match member name json with Some (`Int i) -> Some i | _ -> None

let bool name json =
  match member name json with Some (`Bool b) -> Some b | _ -> None

let list name json = match member name json with Some (`List l) -> l | _ -> []
let unexpected path expected = Error (Unexpected {path; expected})

(* A required field read from a non-object is reported at the object
   itself: the payload's shape is wrong, not one field. *)
let required ~at name expected get json =
  match json with
  | `Assoc _ -> (
      match get json with
      | Some v -> Ok v
      | None -> unexpected (at ^ "/" ^ name) expected)
  | _ -> unexpected at "object"

let required_string ?(at = "") name =
  required ~at name "non-blank string" (string name)

let required_int ?(at = "") name = required ~at name "int" (int name)

let required_list ?(at = "") name =
  required ~at name "array" (fun json ->
      match member name json with Some (`List l) -> Some l | _ -> None)

module Syntax = struct
  let ( let* ) = Result.bind
  let ( let+ ) r f = Result.map f r
end
