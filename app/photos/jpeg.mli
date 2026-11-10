(** JPEG segment reading over the file's bytes. Pure, tested natively in
    [test/photos/]. *)

val has_exif : string -> bool
(** [has_exif bytes] is whether the JPEG [bytes] carry an EXIF segment: an APP1
    ([FF E1]) whose payload starts with ["Exif\000\000"], among the segments
    before the scan data. [false] for bytes that are not a JPEG. *)
