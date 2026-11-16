(** Binding to [@capacitor/filesystem] ([globalThis.herbier.filesystem]). Every
    path is relative to the app-private [Directory.Data]; no other directory is
    reachable (architecture §3). Paths use ['/']; a path that could leave
    [Directory.Data] (absolute, empty, an empty, ["."] or [".."] segment, a
    backslash or a NUL) is [Error (Invalid_path path)] without calling the
    plugin. Valid paths are passed through untouched. *)

val write_text : path:string -> string -> (string, Cap_error.t) result Fut.t
(** Writes UTF-8 text ([encoding: "utf8"]), replacing the file, creating missing
    parent directories ([recursive: true]). Returns the file's [uri]
    (["file://…"]); [Error (Unexpected "uri")] without one. *)

val write_base64 : path:string -> string -> (string, Cap_error.t) result Fut.t
(** Same with binary data given base64-encoded (no [encoding]); the plugin
    decodes it. Non-base64 input is [Error (Rejected _)]. *)

val read_text : path:string -> (string, Cap_error.t) result Fut.t
(** Reads a file as UTF-8 text. A missing file is [Error (Rejected _)] with the
    plugin's code and message (not interpreted). [Error (Unexpected "data")]
    when [data] is not a string. *)

val read_base64 : path:string -> (string, Cap_error.t) result Fut.t
(** Reads a file's bytes, base64-encoded (no [encoding]). Errors as
    {!read_text}. *)

val delete_file : path:string -> (unit, Cap_error.t) result Fut.t
(** Deletes a file; a missing file is [Error (Rejected _)] ({!is_missing}). *)

val is_missing : Cap_error.t -> bool
(** The plugin's « does not exist »: [Rejected] with code ["OS-PLUG-FILE-0008"]
    (@capacitor/filesystem 8 on Android). Any other rejection (permission, IO,
    …) is not. *)

val mkdir : path:string -> recursive:bool -> (unit, Cap_error.t) result Fut.t
(** Creates a directory; [~recursive:true] creates missing parents. An existing
    directory is [Error (Rejected _)] (the plugin's behaviour, not hidden). *)

type kind = File | Directory

type entry = {name : string; kind : kind; size : int}
(** One item of a directory listing: [name] without its directory, [size] in
    bytes (the plugin's [size]; for a directory, whatever the plugin says:
    callers do not use it). *)

val readdir : path:string -> (entry list, Cap_error.t) result Fut.t
(** Lists a directory, in the plugin's order. A missing directory is
    [Error (Rejected _)] ({!is_missing}). [Error (Unexpected "files")] when
    [files] is not an array; [Error (Unexpected "files[<i>].name")] (or [.type],
    [.size]) when item [i] lacks that field, has a [type] other than ["file"] /
    ["directory"], or a [size] that is not an integer. *)

val rmdir : path:string -> recursive:bool -> (unit, Cap_error.t) result Fut.t
(** Removes a directory; [~recursive:true] removes its content too. A missing
    directory is [Error (Rejected _)] ({!is_missing}). *)
