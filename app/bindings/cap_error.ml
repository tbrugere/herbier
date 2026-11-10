type t =
  | Unavailable of string
  | Rejected of {code : string option; message : string}
  | Unexpected of string
  | Invalid_path of string

let to_string = function
  | Unavailable name -> "plugin " ^ name ^ " unavailable"
  | Rejected {code = Some code; message} -> code ^ ": " ^ message
  | Rejected {code = None; message} -> message
  | Unexpected path -> "unexpected plugin result at " ^ path
  | Invalid_path path -> "invalid path " ^ path

let of_jv_error e =
  Rejected {code = None; message = Jstr.to_string (Jv.Error.message e)}
