(** A device image file (a photo's preview [previews/<id>.jpg] or a reference
    thumbnail [refthumbs/…]) in an [<img>]: the file is read, shown through an
    object URL, and the URL revoked once the image has loaded or failed to
    decode. Until then (or when the file is missing) the box shows the striped
    loading state. *)

val v : ?cls:string list -> ?alt:string -> string -> Brr.El.t
(** [v path]; [cls] are added to the wrapper; [alt] is the image's text
    alternative, empty (decorative) by default. *)
