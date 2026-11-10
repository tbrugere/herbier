(** Binding to the WebView's [createImageBitmap]: decodes an image file, with
    its EXIF orientation applied, for drawing on a canvas (architecture §5). *)

type t
(** An [ImageBitmap]. Holds decoded pixels until {!close}. *)

val of_blob : Brr.Blob.t -> (t, Cap_error.t) result Fut.t
(** [createImageBitmap(blob, {imageOrientation: "from-image"})]. A blob that is
    not a decodable image is [Error (Rejected _)]. *)

val width : t -> int
(** Pixels, after orientation. *)

val height : t -> int
val image_src : t -> Brr_canvas.C2d.image_src

val close : t -> unit
(** Frees the pixels; the bitmap is unusable afterwards. *)
