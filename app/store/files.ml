module Cap_error = Herbier_bindings.Cap_error
module Cap_filesystem = Herbier_bindings.Cap_filesystem

let preview id = "previews/" ^ Herbier_domain.Ids.Photo_id.to_string id ^ ".jpg"

(* The filesystem plugin takes binary data as base64. *)
let base64_of_blob blob =
  Fut.map
    (function
      | Error e -> Error (Cap_error.of_jv_error e)
      | Ok buffer ->
          Brr.Tarray.to_binary_jstr
            (Brr.Tarray.of_buffer Brr.Tarray.Uint8 buffer)
          |> Brr.Base64.data_of_binary_jstr
          |> Brr.Base64.encode
          |> Result.map Jstr.to_string
          |> Result.map_error Cap_error.of_jv_error)
    (Brr.Blob.array_buffer blob)

let write_blob ~path blob =
  let open Fut.Result_syntax in
  let* base64 = base64_of_blob blob in
  let+ (_ : string) = Cap_filesystem.write_base64 ~path base64 in
  ()

let blob_of_base64 ~type' base64 =
  let open Result.Syntax in
  let* data = Brr.Base64.decode (Jstr.v base64) in
  let+ bytes =
    Brr.Tarray.of_binary_jstr (Brr.Base64.data_to_binary_jstr data)
  in
  Brr.Blob.of_array_buffer
    ~init:(Brr.Blob.init ~type':(Jstr.v type') ())
    (Brr.Tarray.buffer bytes)

let read_blob ~path ~type' =
  Fut.map
    (fun read ->
      Result.bind read (fun base64 ->
          Result.map_error Cap_error.of_jv_error (blob_of_base64 ~type' base64)))
    (Cap_filesystem.read_base64 ~path)

let delete ~path = Cap_filesystem.delete_file ~path
