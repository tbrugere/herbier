(** Dev-only page for the photo bindings: a button picks photos from the gallery
    and lists, for each, what {!Herbier_photos.Exif} reads from it through
    exifr; another asks for one GPS fix. Reached with the URL fragment
    [#dev/photos]. Writes nothing. *)

val el : unit -> Brr.El.t
