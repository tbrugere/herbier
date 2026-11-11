(** A photo's device preview ([previews/<id>.jpg]) in an [<img>]: the file is
    read, shown through an object URL, and the URL revoked once the image has
    loaded or failed to decode. Until then (or when the file is missing) the box
    shows the striped loading state. *)

val v : ?cls:string -> string -> Brr.El.t
(** [v path]; [cls] is added to the wrapper. *)
