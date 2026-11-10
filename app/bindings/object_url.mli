(** Binding to [URL.createObjectURL] / [URL.revokeObjectURL]: a [blob:] URL an
    [<img>] reads a blob through, without copying it into a [data:] URI. *)

val create : Brr.Blob.t -> Jstr.t
(** A new [blob:] URL for the blob. It keeps the blob alive until {!revoke}. *)

val revoke : Jstr.t -> unit
(** Releases the URL; an element already loaded from it keeps its image. *)
