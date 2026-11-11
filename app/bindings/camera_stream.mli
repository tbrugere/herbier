(** The in-app viewfinder's camera (architecture §5, 4d): [getUserMedia] on the
    back camera, shown in a [<video>], [ImageCapture.takePhoto] and a frame of
    the [<video>]. Which still the shutter takes is the caller's choice. *)

type t
(** A live [MediaStream]. *)

val start : unit -> (t, Cap_error.t) result Fut.t
(** [navigator.mediaDevices.getUserMedia] for video only, preferring the back
    camera ([facingMode: "environment"]) and the largest frame it offers (ideal
    4096 × 3072). No camera, no [mediaDevices] (an insecure origin) or the
    permission refused is [Error (Rejected _)] with the [DOMException]'s name as
    [code] (["NotAllowedError"], ["NotFoundError"], ["NotSupportedError"]). *)

val attach : t -> Brr.El.t -> unit
(** Shows the stream in a [<video>] element: sets [srcObject], [muted],
    [playsInline] and calls [play()] (a rejection of its promise is dropped: a
    paused preview is not an error). *)

val stop : t -> unit
(** Stops every track: the camera light goes off. Idempotent. *)

val live : t -> bool
(** The stream's video track is still running ([readyState] ["live"]): false
    after {!stop}, or once the system ended it (another app took the camera). *)

val has_image_capture : unit -> bool
(** [ImageCapture] exists (Chrome, Android WebView). *)

val take_photo : t -> (Brr.Blob.t, Cap_error.t) result Fut.t
(** [new ImageCapture(track).takePhoto()] on the stream's video track: a JPEG at
    the sensor's photo resolution, which may carry the camera's EXIF
    (orientation, date) but no GPS. Without [ImageCapture] or a video track, or
    when [takePhoto] rejects, [Error (Rejected _)] with the [DOMException]'s
    name as [code]. *)

val frame : Brr.El.t -> quality:float -> (Brr.Blob.t, Cap_error.t) result Fut.t
(** The [<video>]'s current frame at its intrinsic size, drawn on a canvas and
    encoded as JPEG at [quality] (no EXIF). A video with no frame yet
    ([videoWidth] 0) is [Error (Unexpected "videoWidth")]. *)
