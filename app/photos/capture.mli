(** Getting photos in (architecture §5, 4d): the in-app viewfinder's shutter and
    the gallery pick, each giving the original bytes, what is known of when and
    where, and an in-memory preview for the thumbnail row. Nothing is written
    here: the preview file and the photo row are written when the observation is
    saved ({!Preview.save}). *)

type source = Shutter | Gallery

type shot = {
  original : Brr.Blob.t;
      (** the bytes as captured: what sha256 and Drive get *)
  source : source;
  exif : Exif.t;
      (** a gallery photo's own date and position (the picker may strip GPS); a
          shutter still has none, it is now and here *)
  preview : Preview.t;
}

type error =
  | Camera of Herbier_bindings.Cap_error.t
      (** no camera, permission refused, or no frame yet *)
  | Stopped
      (** the viewfinder's camera is no longer running: closed, or ended by the
          system (another app took the camera) *)
  | Pick of Herbier_bindings.Cap_error.t
      (** the picker failed or was cancelled *)
  | Fetch of string  (** a picked file could not be read back; the message *)
  | Preview of Preview.error

val error_to_string : error -> string

(** {1 Viewfinder} *)

type viewfinder

val open_viewfinder : video:Brr.El.t -> (viewfinder, error) result Fut.t
(** Starts the back camera and shows it in [video] (a [<video>]). *)

val shutter : viewfinder -> (shot, error) result Fut.t
(** A still from the camera and its preview: [ImageCapture]'s photo at the
    sensor's resolution, or, without it or when it fails (the failure is
    logged), the viewfinder's current frame as JPEG {!frame_quality}. [exif] is
    {!Exif.empty}: the caller dates and places the photo itself. After
    {!close_viewfinder} it is [Error Stopped]. *)

val frame_quality : float
(** 0.92: a frame becomes the photo's original (what Drive keeps), so it is
    encoded close to lossless. *)

val close_viewfinder : viewfinder -> unit
(** Stops the camera. Idempotent; call it when the viewfinder's screen is left.
*)

(** {1 Gallery} *)

val pick : limit:int -> (shot list, error) result Fut.t
(** The system picker, several photos at once (at most [limit] on Android 13+, a
    non-positive [limit] is none; see
    {!Herbier_bindings.Cap_camera.choose_photos}); each one's EXIF is read from
    its original bytes before its preview is made. A photo whose EXIF cannot be
    read keeps {!Exif.empty}; one that cannot be decoded fails the whole pick.
*)
