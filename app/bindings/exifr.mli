(** Binding to exifr ([globalThis.herbier.exifr]), the EXIF reader of the photo
    pipeline (architecture §5): it runs on the original bytes, before any canvas
    work, since a canvas re-encode drops the EXIF. *)

val parse :
  pick:string list -> Brr.Blob.t -> (string option, Cap_error.t) result Fut.t
(** [parse ~pick blob] is
    [exifr.parse(blob, {pick, reviveValues: false, translateValues: false})]:
    only the tags in [pick], with dates left as the strings the camera wrote
    (exifr would otherwise read a date without offset in the WebView's time
    zone). exifr adds the decimal [latitude] and [longitude] it computes when
    the GPS tags are picked. The result is the JSON text of that object; [None]
    when the file has none of those tags. A file exifr cannot read (not an
    image, a truncated file) is [Error (Rejected _)]. *)
