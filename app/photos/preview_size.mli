(** The size and quality of a device preview (architecture §5). Pure, tested
    natively in [test/photos/]. *)

val max_side : int
(** [1600]: the preview's long side, in pixels, at most. *)

val quality : float
(** [0.7]: the JPEG quality the preview is encoded at. *)

val fit : width:int -> height:int -> int * int
(** The preview's size for an original of [width] × [height]: scaled so the long
    side is at most {!max_side}, aspect ratio kept (rounded), never upscaled,
    never below 1 × 1. *)
