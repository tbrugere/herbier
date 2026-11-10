(** The device preview of a photo (architecture §5): the original decoded with
    its orientation, resized to at most {!Preview_size.max_side} pixels on its
    long side, drawn over white, re-encoded as JPEG at {!Preview_size.quality},
    which leaves no EXIF in it, and written to [previews/<id>.jpg]. *)

module Photo = Herbier_domain.Photo
module Observation_id = Herbier_domain.Ids.Observation_id

type error =
  | Decode of Herbier_bindings.Cap_error.t
      (** The original is not an image the WebView decodes. *)
  | Encode of Herbier_bindings.Cap_error.t
      (** Drawing on the canvas threw ([Rejected _]), or the canvas produced no
          blob ([Unexpected "blob"]: empty canvas, out of memory) or [toBlob]
          threw ([Rejected _]). *)
  | Not_jpeg of string
      (** The WebView encoded another type (it falls back to PNG for a type it
          cannot encode); carries that type. *)
  | Hash of string  (** WebCrypto's digest failed; its message. *)
  | Read_original of Herbier_bindings.Cap_error.t
      (** The original's bytes could not be read (for its hash). *)
  | Write_preview of Herbier_bindings.Cap_error.t
      (** The preview file was not written. *)
  | Store of Herbier_store.Db.error  (** The photo row was not written. *)

val error_to_string : error -> string

type t = {jpeg : Brr.Blob.t; width : int; height : int}

val make : Brr.Blob.t -> (t, error) result Fut.t
(** Decodes, resizes and encodes the original. *)

val sha256_hex : Brr.Blob.t -> (string, error) result Fut.t
(** Lowercase hex SHA-256 of the blob's bytes: the original as captured. *)

val save :
  Herbier_store.Db.t ->
  observation_id:Observation_id.t ->
  taken_at:Ptime.t ->
  original_target:Photo.Original_target.t ->
  Brr.Blob.t ->
  (Photo.t, error) result Fut.t
(** [save db ~observation_id ~taken_at ~original_target original] hashes the
    original, makes its preview, writes it to [Files.preview id] and inserts the
    photo row ([upload_state = Pending], through [Db.edit], so with its outbox
    entry). The file is written before the row, so a row never points to a
    missing preview; when the write or the row fails the file is deleted again
    (a failure of that delete is ignored: an orphan preview is harmless). The
    observation row must exist (foreign key). *)
