let parse s =
  match Yojson.Safe.from_string s with
  | json -> Ok json
  | exception Yojson.Json_error msg -> Error msg
  (* style §8.4: under js_of_ocaml a deeply nested text raises Failure (a JS
     stack overflow), not Json_error; parse never raises. *)
  | exception e -> Error (Printexc.to_string e)

let member name = function
  | `Assoc fields -> (
      match List.assoc_opt name fields with
      | None | Some `Null -> None
      | Some v -> Some v)
  | _ -> None

let string_member name json =
  match member name json with Some (`String s) -> Some s | _ -> None

let number = function
  | `Int i -> Some (Float.of_int i)
  | `Float f when Float.is_finite f -> Some f
  | _ -> None

let is_digits s =
  s <> "" && String.for_all (function '0' .. '9' -> true | _ -> false) s
