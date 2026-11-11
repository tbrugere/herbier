(* Reads one recorded payload from test/fixtures/, as raw text: tests decode
   it the way the app would, via Decode.json_of_string or an inline Yojson
   literal, never here. *)

let read name =
  let path = Filename.concat "../fixtures" name in
  In_channel.with_open_bin path In_channel.input_all

let exists name = Sys.file_exists (Filename.concat "../fixtures" name)
