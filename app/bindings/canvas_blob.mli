(** [HTMLCanvasElement.toBlob] with an encoding. [Brr_canvas.Canvas.to_blob]
    drops its [~encode] argument (brr 0.0.9 always passes ["image/png"]), so
    this binding passes the type and quality. *)

val to_blob :
  Brr_canvas.Canvas.t ->
  type':string ->
  quality:float ->
  (Brr.Blob.t, Cap_error.t) result Fut.t
(** [toBlob(callback, type', quality)]. The browser falls back to PNG for a type
    it cannot encode; a [null] blob (empty canvas, out of memory) is
    [Error (Unexpected "blob")]; a throw (tainted canvas) is
    [Error (Rejected _)]. *)
