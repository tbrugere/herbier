module Col = Postgrest.Col
module Row = Postgrest.Row

type param = Null | Int of int | Float of float | Text of string

(* ptime renders offset 0 as "Z" and always prints six fractional digits,
   truncating the rest, so every encoding has the same width. *)
let timestamp t = Ptime.to_rfc3339 ~frac_s:6 ~tz_offset_s:0 t

let base_param : type a. a Col.base -> a -> param =
 fun base v ->
  match base with
  | Integer -> Int v
  | Numeric -> Float v
  | Bool -> ( match v with true -> Int 1 | false -> Int 0)
  | Str -> Text v
  | Custom c -> Text (Col.encode_base (Custom c) v)
  | TimestampTz -> Text (timestamp v)
  | JSON -> Text (Yojson.Safe.to_string v)

let param : type a. ('table, a, 'optional) Col.t -> a -> param =
 fun {ty; name = _} v ->
  match ty with
  | Not_Null base -> base_param base v
  | Nullable base -> (
      match v with None -> Null | Some v -> base_param base v)

type 'table json_column = string

let json (c : (_, Yojson.Safe.t, _) Col.t) = c.name

type error =
  | Invalid_row of string
  | Invalid_json_column of string
  | Row of Row.error

(* Yojson's messages span two lines ("Line 1, bytes 0-4:\nInvalid token"). *)
let one_line s = String.map (function '\n' | '\r' -> ' ' | c -> c) s

let error_to_string = function
  | Invalid_row msg -> "invalid row: " ^ one_line msg
  | Invalid_json_column name -> "column " ^ name ^ " is not JSON text"
  | Row `Missing -> "missing column"
  | Row `NotAnObject -> "not an object"
  | Row `WrongType -> "wrong type"
  | Row `UnexpectedNull -> "unexpected null"
  | Row `DummyRow -> "dummy row spec"

let parse_object text =
  match Yojson.Safe.from_string text with
  | `Assoc fields -> Ok fields
  | _ -> Error (Invalid_row "not an object")
  | exception Yojson.Json_error msg -> Error (Invalid_row msg)

let parse_json_column fields name =
  match List.assoc_opt name fields with
  | Some (`String text) -> (
      match Yojson.Safe.from_string text with
      | value -> Ok ((name, value) :: List.remove_assoc name fields)
      | exception Yojson.Json_error _ -> Error (Invalid_json_column name))
  | Some _ | None -> Ok fields

let decode_object spec fields =
  (* Row.decode calls int_of_string on an integer literal too large for an
     int; database data must not raise (style 8.3). *)
  match Row.decode spec (`Assoc fields) with
  | result -> Result.map_error (fun e -> Row e) result
  | exception Failure _ -> Error (Row `WrongType)

let parse_json_columns fields json =
  List.fold_left
    (fun acc name -> Result.bind acc (fun f -> parse_json_column f name))
    (Ok fields) json

let decode ~json spec text =
  match parse_object text with
  | Error e -> Error e
  | Ok fields -> (
      match parse_json_columns fields json with
      | Error e -> Error e
      | Ok fields -> decode_object spec fields)
