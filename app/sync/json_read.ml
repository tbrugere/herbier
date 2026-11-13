let object_of_string text =
  match Yojson.Safe.from_string text with
  | `Assoc fields -> Ok fields
  | _ -> Error "not an object"
  | exception Yojson.Json_error _ -> Error "not JSON"

let version v fields =
  match List.assoc_opt "v" fields with
  | Some (`Int n) when Int.equal n v -> Ok ()
  | Some _ -> Error "unknown version"
  | None -> Error "no version"

let versioned v text =
  let open Result.Syntax in
  let* fields = object_of_string text in
  let+ () = version v fields in
  fields
