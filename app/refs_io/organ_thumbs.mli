(** The organ photos of one plant on the device (architecture §6): its
    [ref_images] rows follow its live Pl@ntNet reference row, and the missing
    thumbnails are downloaded into [refthumbs/]. *)

module Organ := Herbier_domain.Reference.Organ
module Db := Herbier_store_io.Db
module Cap_error := Herbier_bindings.Cap_error

(** Why a thumbnail was not had. The row keeps [thumb_path = None] and the next
    sync tries again. *)
type failure =
  | Host
      (** The URL is not [Organ_photos.downloadable]: not fetched.
          [Organ_photos.wanted] already leaves such URLs out, so a sync does not
          reach this. *)
  | Download of Cap_error.t  (** The GET failed (network, DNS, timeout). *)
  | Http of int  (** A status other than 2xx (redirects are not followed). *)
  | Too_large of int
      (** The body, base64-encoded, is longer than {!max_base64}; its length. *)
  | Base64 of Cap_error.t
  | Decode of Cap_error.t  (** [Image_bitmap.of_blob]. *)
  | Draw of Cap_error.t
  | Encode of Cap_error.t
  | Not_jpeg of string  (** The WebView encoded another type; that type. *)
  | Write of Cap_error.t
  | Stale
      (** The file was written but the row changed or went meanwhile
          ([Ref_images.set_thumb] changed nothing). *)

type outcome = failure Herbier_refs.Organ_photos.outcome
(** [Herbier_refs.Organ_photos.outcome]: its constructors are there. *)

type report = (Organ.t * outcome) list
(** {!Herbier_refs.Organ_photos.report}: organs touched or present, in
    [Organ.all] order. *)

val failure_to_string : failure -> string
(** ["host"], ["download: <error>"], ["HTTP <status>"], ["too large: <n>"],
    ["base64: <error>"], ["decode: <error>"], ["draw: <error>"],
    ["encode: <error>"], ["encode: the WebView produced <type>, not JPEG"],
    ["write: <error>"], ["stale"]. *)

val outcome_to_string : outcome -> string
(** ["present"], ["updated"], ["downloaded"], ["removed"],
    ["failed: <failure>"]. *)

val changed : report -> bool
(** {!Herbier_refs.Organ_photos.changed}: the fiche should reload. *)

val default_timeout_ms : int
(** 20 000. *)

val max_base64 : int
(** 16 000 000 characters (about 12 MB of image): a longer body is not decoded.
    The transfer itself is not bounded (the plugin reads the whole body). *)

val sync :
  ?timeout_ms:int ->
  Db.t ->
  plant:Herbier_domain.Ids.Plant_id.t ->
  (report, Db.error) result Fut.t
(** Reads [References.of_plant] and [Ref_images.of_plant]; takes
    [Projection.organ_photos_wanted] of the references' projection; applies
    [Organ_photos.plan] with {!Db.write}, one statement at a time ([remove]
    first, then [put]); deletes the file of each removed row that had one (a
    delete error is ignored: the file is left as an orphan); then, one at a time
    in organ order, for each [Organ_photos.to_download] of the rows read back:
    [Cap_http.get_bytes], [Files.blob_of_base64 ~type':"image/jpeg"],
    [Image_bitmap.of_blob], draw at [Organ_photos.fit] on a white canvas, JPEG
    at [Organ_photos.quality], [Files.write_blob] at [Files.refthumb], then
    [Ref_images.set_thumb]. Each step's failure is the {!failure} of that name.

    Not reentrant for one plant: the file path depends only on the row's key, so
    two overlapping syncs of a plant could leave an older image under a newer
    row. The caller runs at most one sync per plant at a time ([App.sync_thumbs]
    does).

    A read or write error of the database is [Error] (rows written before it
    stay: the table is a cache). Never raises; the bitmap is closed on every
    path. Downloads do not go through [Http]'s queue: one at a time within a
    sync, syncs of different plants may overlap. *)
