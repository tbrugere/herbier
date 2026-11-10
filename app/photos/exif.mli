(** The EXIF fields the photo pipeline keeps (architecture §5), decoded from the
    JSON text {!Herbier_bindings.Exifr.parse} returns. Pure: no Brr, so it is
    tested natively (test/photos/). A field that is missing or does not parse is
    [None]; it never fails the photo (style guide §8.4). *)

val tags : string list
(** The tags {!Herbier_bindings.Exifr.parse} must pick for {!of_json}: the ones
    it reads, and [GPSLatitude] / [GPSLongitude], from which exifr computes the
    [latitude] and [longitude] it reads (scripts/exifr-fixture.mjs picks the
    same list). *)

type t = {
  taken_at : Ptime.t option;
      (** [DateTimeOriginal], with [SubSecTimeOriginal] (truncated to
          microseconds, the store's precision) and the offset of
          [OffsetTimeOriginal]. *)
  position : Herbier_domain.Observation.position option;
      (** exifr's decimal [latitude] / [longitude], with [GPSHPositioningError]
          as [accuracy_m] when it is a positive number. *)
}

val empty : t
(** Both fields [None]: a photo without EXIF ([Exifr.parse] gave [None]). *)

val of_json :
  tz_offset_at:(Ptime.date -> int * int * int -> int) -> Yojson.Safe.t -> t
(** [of_json ~tz_offset_at json] reads an exifr object.

    [taken_at]: [DateTimeOriginal] must be ["YYYY:MM:DD HH:MM:SS"], a valid date
    and time; cameras write ["0000:00:00 00:00:00"] or blanks when the clock was
    unset, which give [None]. [OffsetTimeOriginal] (["+HH:MM"] or ["-HH:MM"])
    gives the offset; without it, or when it does not parse, the wall-clock time
    is read at [tz_offset_at date (hh, mm, ss)]: seconds east of UTC of the
    device's time zone at that local time (so a July photo picked in November
    gets its summer offset; {!Herbier_bindings.Js_date.local_offset_s}).
    [SubSecTimeOriginal] is ASCII digits after the decimal point; anything else
    is ignored.

    [position]: both [latitude] and [longitude] must be finite numbers in
    [[-90, 90]] and [[-180, 180]], and [GPSLatitudeRef] must be ["N"] or ["S"]
    and [GPSLongitudeRef] ["E"] or ["W"] (exifr signs the coordinates from
    exactly those values and assumes N and E otherwise, which would put a
    southern or western photo in the wrong hemisphere); exactly [(0, 0)], which
    phones write without a fix, is [None]. A non-object [json] is {!empty}. *)

val of_string :
  tz_offset_at:(Ptime.date -> int * int * int -> int) -> string -> t
(** {!of_json} of JSON text; text that is not JSON is {!empty}. *)
