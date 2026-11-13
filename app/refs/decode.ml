module Json = Herbier_net.Json

type error =
  | Not_json of string
  | Unexpected of {path : string; expected : string}
  | Api_error of {code : string; info : string}
[@@deriving eq, show]

let error_to_string = function
  | Not_json msg -> "not JSON: " ^ msg
  | Unexpected {path; expected} ->
      Printf.sprintf "unexpected payload at %S: expected %s" path expected
  | Api_error {code; info} -> Printf.sprintf "API error %s: %s" code info

let json_of_string s = Result.map_error (fun m -> Not_json m) (Json.parse s)
let non_blank s = match String.trim s with "" -> None | _ -> Some s

let string name json =
  match Json.member name json with Some (`String s) -> non_blank s | _ -> None

let int name json =
  match Json.member name json with Some (`Int i) -> Some i | _ -> None

let bool name json =
  match Json.member name json with Some (`Bool b) -> Some b | _ -> None

let list name json =
  match Json.member name json with Some (`List l) -> l | _ -> []

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
      match Json.member name json with Some (`List l) -> Some l | _ -> None)

module Syntax = struct
  let ( let* ) = Result.bind
  let ( let+ ) r f = Result.map f r
end
