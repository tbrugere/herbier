(** The app's files under [Directory.Data] (architecture §3): their paths, and
    blobs written and read through {!Herbier_bindings.Cap_filesystem}. *)

val preview : Herbier_domain.Ids.Photo_id.t -> string
(** ["previews/<photo id>.jpg"]. *)

val write_blob :
  path:string -> Brr.Blob.t -> (unit, Herbier_bindings.Cap_error.t) result Fut.t
(** Writes the blob's bytes at [path], replacing the file and creating missing
    directories. Errors are the filesystem binding's, or [Rejected _] when the
    blob cannot be read. Not atomic: a write that fails partway can leave a
    truncated file at [path], so rewriting a file a row points to needs a
    temporary file and a rename. *)

val read_blob :
  path:string ->
  type':string ->
  (Brr.Blob.t, Herbier_bindings.Cap_error.t) result Fut.t
(** The file's bytes as a blob of MIME type [type']. *)

val delete : path:string -> (unit, Herbier_bindings.Cap_error.t) result Fut.t
(** Deletes the file; a missing file is [Error (Rejected _)]. *)
