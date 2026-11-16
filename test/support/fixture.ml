let dir = "../fixtures"
let path name = Filename.concat dir name
let read name = In_channel.with_open_bin (path name) In_channel.input_all
let exists name = Sys.file_exists (path name)

let names ~prefix =
  Sys.readdir dir
  |> Array.to_list
  |> List.filter (String.starts_with ~prefix)
  |> List.sort String.compare
