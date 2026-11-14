let plugin = "filesystem"

(* The string values of the plugin's Directory.Data and Encoding.UTF8 enum
   members, which vendor.js does not export. *)
let data_dir = ("directory", Jv.of_string "DATA")
let utf8 = ("encoding", Jv.of_string "utf8")
let options fields = [|Jv.obj (Array.of_list fields)|]
let uri r = Cap_call.string_field r "uri"
let data r = Cap_call.string_field r "data"
let unit_ok = Cap_call.unit_ok

(* Keeps every path inside Directory.Data: the plugin resolves [path]
   against it as is, so ".." would reach the app's other private files. *)
let valid_segment = function
  | "" | "." | ".." -> false
  | seg -> not (String.contains seg '\\' || String.contains seg '\000')

let checked path f =
  match List.for_all valid_segment (String.split_on_char '/' path) with
  | true -> f (Jv.of_string path)
  | false -> Fut.return (Error (Cap_error.Invalid_path path))

let write_text ~path text =
  checked path (fun jpath ->
      Cap_call.call plugin "writeFile"
        (options
           [
             ("path", jpath);
             ("data", Jv.of_string text);
             data_dir;
             utf8;
             ("recursive", Jv.true');
           ])
        ~ok:uri)

let write_base64 ~path base64 =
  checked path (fun jpath ->
      Cap_call.call plugin "writeFile"
        (options
           [
             ("path", jpath);
             ("data", Jv.of_string base64);
             data_dir;
             ("recursive", Jv.true');
           ])
        ~ok:uri)

let read_text ~path =
  checked path (fun jpath ->
      Cap_call.call plugin "readFile"
        (options [("path", jpath); data_dir; utf8])
        ~ok:data)

let read_base64 ~path =
  checked path (fun jpath ->
      Cap_call.call plugin "readFile"
        (options [("path", jpath); data_dir])
        ~ok:data)

let delete_file ~path =
  checked path (fun jpath ->
      Cap_call.call plugin "deleteFile"
        (options [("path", jpath); data_dir])
        ~ok:unit_ok)

let mkdir ~path ~recursive =
  checked path (fun jpath ->
      Cap_call.call plugin "mkdir"
        (options
           [("path", jpath); data_dir; ("recursive", Jv.of_bool recursive)])
        ~ok:unit_ok)

let is_missing : Cap_error.t -> bool = function
  | Rejected {code = Some "OS-PLUG-FILE-0008"; _} -> true
  | Rejected _ | Unavailable _ | Unexpected _ | Invalid_path _ -> false
