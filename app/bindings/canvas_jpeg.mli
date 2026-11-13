(** A bitmap drawn on a canvas and encoded as JPEG, at the size and quality the
    caller picks. *)

val mime : string
(** ["image/jpeg"]. *)

val draw :
  width:int ->
  height:int ->
  Image_bitmap.t ->
  (Brr_canvas.Canvas.t, Cap_error.t) result
(** A [width] × [height] canvas filled white, then the bitmap drawn over it,
    scaled with high-quality smoothing. The bitmap is closed whatever happens. A
    JS [Error] thrown while drawing is [Error (Rejected _)]; any other exception
    (jsoo raises a thrown non-[Error] value as [Failure]) is re-raised. *)

type encode_error =
  | Encode of Cap_error.t  (** [toBlob] failed *)
  | Not_jpeg of string
      (** the WebView produced this other type (it falls back to PNG for a type
          it cannot encode) *)

val encode :
  quality:float ->
  Brr_canvas.Canvas.t ->
  (Brr.Blob.t, encode_error) result Fut.t
(** The canvas as a {!mime} blob at [quality]. *)
