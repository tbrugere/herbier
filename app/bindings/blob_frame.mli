(** [new Blob([prefix, blob, suffix])]: a blob's bytes between two texts, the
    texts encoded as UTF-8 (a multipart upload's frame around a photo, which a
    string body would corrupt). Brr has no constructor from parts. *)

val wrap : prefix:string -> suffix:string -> Brr.Blob.t -> Brr.Blob.t
(** The new blob has no type (the request's Content-Type says it). The bytes of
    the middle blob are not copied into OCaml. *)
