let path name = Filename.concat "../fixtures" name
let read name = In_channel.with_open_bin (path name) In_channel.input_all
let exists name = Sys.file_exists (path name)
