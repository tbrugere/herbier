(** Typed identifiers. One abstract type per synced table, all UUIDs underneath,
    so a plant id cannot be passed where an observation id is expected. Ids are
    generated on the device (architecture §4). They are not secrets: the
    generator is not cryptographic, and row access is enforced by RLS on
    [owner_id], not by unguessable ids. *)

module type S = sig
  type t

  val fresh : unit -> t
  (** A new time-ordered (version 7) UUID: 48 bits of millisecond POSIX time
      from [Ptime_clock.now], then a per-millisecond counter and random bits.
      Ids minted in a row on one device sort in minting order, by [compare] and
      as strings, as long as the clock does not go backwards and fewer than 4096
      are minted within one millisecond; past that the order inside the
      millisecond is random. Never fails, never raises. The random bits are
      seeded once, lazily, from the platform's entropy through
      [Random.State.make_self_init] ([crypto.getRandomValues] under js_of_ocaml,
      which falls back to a time-based seed if [crypto] is absent). *)

  val of_string : string -> t option
  (** Parses the canonical 36-character textual form
      [xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx], hex digits in either case. [None]
      for anything else: wrong length (including trailing or leading characters
      or whitespace), missing or misplaced hyphens, non-hex digits, braces, the
      32-digit hyphen-less form. Any version/variant is accepted (including the
      nil UUID): rows written by Postgres or other tools are not rejected for
      their version nibble. *)

  val to_string : t -> string
  (** Canonical lowercase 36-character form.
      [of_string (to_string id) = Some id] for every [id]; [to_string] of a
      parsed uppercase string is its lowercase spelling. *)

  val equal : t -> t -> bool
  (** Equality of the UUID value: ids parsed from the same UUID in different
      letter case are equal. *)

  val compare : t -> t -> int
  (** Total order consistent with [equal]; the lexicographic order of
      [to_string]. *)

  val pp : Format.formatter -> t -> unit
  (** Prints [to_string]. *)
end

module Plant_id : S
module Observation_id : S
module Photo_id : S
module Tag_id : S
module Plant_tag_id : S
module Plant_ref_id : S
module Reference_id : S
