(** Dev-only page [#dev/capture]: the viewfinder in a [<video>], a shutter and a
    gallery button. Each shot's preview is written to [dev/capture-<n>.jpg],
    read back and shown with its size. Writes no row. « Fermer » stops the
    camera, also when it is pressed while the camera is still opening. *)

val el : unit -> Brr.El.t
