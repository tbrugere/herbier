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
(** Deletes a file; a missing file is [Error (Rejected _)]. *)

val mkdir : path:string -> recursive:bool -> (unit, Cap_error.t) result Fut.t
(** Creates a directory; [~recursive:true] creates missing parents. An existing
    directory is [Error (Rejected _)] (the plugin's behaviour, not hidden). *)
