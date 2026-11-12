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

  val to_json : t -> Yojson.Safe.t
  (** The JSON string [to_string t]: a uuid column value as PostgREST sends and
      receives it. *)

  val of_json : Yojson.Safe.t -> t option
  (** [of_string] of a JSON string; [None] for any other JSON value. *)
end

module Plant_id : S
module Observation_id : S
module Photo_id : S
module Tag_id : S

module Plant_tag_id : sig
  include S

  val of_key : plant:Plant_id.t -> tag:Tag_id.t -> t
  (** The id of the [plant_tags] row for [(plant, tag)] (architecture §4): the
      UUID v5 under the Herbier namespace [b85c6db9-9479-4fb1-af57-3ff6ad665b62]
      of the name
      ["plant_tags/" ^ Plant_id.to_string plant ^ "/" ^ Tag_id.to_string tag]
      (canonical lowercase forms). Deterministic across installs and runs;
      distinct pairs give distinct ids (barring SHA-1 collisions); swapping the
      two uuids gives a different id. Never raises. *)
end

module Plant_ref_id : sig
  include S

  val of_key : plant:Plant_id.t -> source:string -> t
  (** The id of the [plant_refs] row for [(plant, source)] (architecture §4):
      the UUID v5 under the Herbier namespace of the name
      ["plant_refs/" ^ Plant_id.to_string plant ^ "/" ^ source]. [source] is the
      stored label, used as given (no trimming, no case folding): callers go
      through [Reference.Plant_ref.id_of_key], which takes a [Source.t].
      Deterministic across installs; never raises. *)
end

module Reference_id : sig
  include S

  val of_key : plant:Plant_id.t -> source:string -> t
  (** Same, of the name ["reference/" ^ Plant_id.to_string plant ^ "/" ^ source]
      (the table is [reference], singular); callers go through
      [Reference.id_of_key]. *)
end
