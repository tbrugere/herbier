(** The « IGN hors-ligne » packs on the device (architecture §3, §8): a
    département's communes downloaded from the Géoplateforme WFS through
    {!Geocoder} (logged like every geocode request), simplified by {!Communes},
    written under [communes/] ({!Herbier_store.Files}) and listed in the
    [commune_packs] table ({!Herbier_store.Commune_packs}). Nothing here raises.

    A download holds {!Geocoder}'s one in-flight slot for its whole transfer (up
    to {!download_timeout_ms}): place-name reverses and 5b searches wait behind
    it, then run with their own timeout. The spacing between two Géoplateforme
    requests still applies to it. *)

type error =
  | Fetch of Geocoder.error  (** the request, its HTTP status or its payload *)
  | File of Herbier_bindings.Cap_error.t
  | Store of Herbier_store.Db.error

val error_to_string : error -> string

val download_timeout_ms : int
(** [120_000]: about 1 MB of gzip for the largest département, on mobile. *)

val departements : unit -> (Communes.departement list, error) result Fut.t
(** [Geocoder.run ~timeout_ms:download_timeout_ms] of
    [Communes.departements_request] decoded by [Communes.departements]. No
    [allow]: a deliberate tap in 4m, which sends no position. *)

val download :
  Herbier_store.Db.t ->
  now:Ptime.t ->
  Communes.departement ->
  (Herbier_store.Commune_packs.t * Communes.pack, error) result Fut.t
(** [Communes.communes_request] through [Geocoder.run ~timeout_ms] →
    [Communes.pack_of_payload] (an exception there →
    [Fetch (Payload (Unexpected {path = ""; _}))]) → [Communes.to_string] →
    written at [Files.commune_pack ~departement ~stamp] ([stamp] the
    milliseconds of [now]: a fresh path, the old file stays until the row points
    to the new one) → [Db.write (Herbier_store.Commune_packs.put row)],
    [size_bytes] the byte length of the text. Then the previous row's file, if
    any and different, is deleted (a failure there is logged, [communes: …], not
    an error). A failed file write ([File]) or a read or write error of the
    table ([Store]) deletes the new file, best effort: a write that failed
    partway leaves no truncated file. A crash between the file and the row
    leaves an orphan file under [communes/] (architecture §3). *)

val delete : Herbier_store.Db.t -> Communes.Code.t -> (unit, error) result Fut.t
(** Reads the département's row; none → [Ok ()]. Deletes the row first, then its
    file: a row is never left pointing to a deleted file. A file that cannot be
    deleted (missing included) is logged, not an error. *)

type loaded = {
  index : Communes.t;  (** the packs whose file was read *)
  rows : (Communes.Code.t * Herbier_store.Commune_packs.t) list;
      (** every row whose code passes [Communes.Code.of_string], in order *)
  unreadable : Communes.Code.t list;
      (** codes whose file failed to read or decode *)
}

val load : Herbier_store.Db.t -> (loaded, error) result Fut.t
(** [Herbier_store.Commune_packs.all] (a row whose code fails
    [Communes.Code.of_string] is logged and skipped), then each file read and
    [Communes.of_string]'d one after the other; a file that fails to read or
    decode, holds another département than its row, or makes the decoder raise
    is logged and its code goes to [unreadable] (the pack is listed, not used).
    Only a failed read of the table fails the load ([Store]): the future is
    always determined. *)
