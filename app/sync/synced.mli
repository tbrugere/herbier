(** The seven synced tables (architecture §4) as one value each: their PostgREST
    table, how a row decodes (the store's row specs) and encodes
    ([Postgrest.Input], the outbox payload's shape), and the merge rule. Pure:
    no Brr, Fut, Jv or bindings (test/sync copies it). *)

module Tables := Herbier_store.Tables
module D := Herbier_domain

type ('table, 'row) t
(** One synced table: its [Tables] columns, the store's row spec and input, and
    its domain [equal]. *)

type any = Any : ('table, 'row) t -> any

val plants : (Tables.Plants.t, D.Plant.t) t
val tags : (Tables.Tags.t, D.Tag.t) t
val observations : (Tables.Observations.t, D.Observation.t) t
val photos : (Tables.Photos.t, D.Photo.t) t
val plant_tags : (Tables.Plant_tags.t, D.Tag.Plant_tag.t) t
val plant_refs : (Tables.Plant_refs.t, D.Reference.Plant_ref.t) t
val reference : (Tables.Reference.t, D.Reference.t) t

val all : any list
(** Pull order, parents first: plants, tags, observations, photos, plant_tags,
    plant_refs, reference. Every foreign key of a table points to a table
    earlier in the list, except [plants.cover_photo_id] (not a local foreign
    key, architecture §3). *)

val name : ('table, 'row) t -> string
(** [Postgrest.Col.name_of_table (table t)]: ["plants"], …, ["reference"]. *)

val of_name : string -> any option
(** Inverse of {!name} on exact strings; [None] otherwise. *)

val table : ('table, 'row) t -> 'table Postgrest.Col.table

val row : ('table, 'row) t -> ('table, 'row) Postgrest.Row.t
(** [Plants.row], [Tags.row], [Observations.row], [Photos.row],
    [Tags.plant_tag_row], [References.plant_ref_row], [References.row]. *)

val input : ('table, 'row) t -> 'row -> ('table, [`Full]) Postgrest.Input.t
(** [Plants.input], …, [References.input]: every column of [Tables]. *)

val order : ('table, 'row) t -> ('table, Ptime.t * string) Postgrest.Row.t
(** [updated_at] then [id]: renders as ["updated_at,id"] in [order=]. *)

val updated_at_col :
  ('table, 'row) t -> ('table, Ptime.t, [`Mandatory]) Postgrest.Col.t

val decide :
  ('table, 'row) t ->
  pending:bool ->
  local:'row option ->
  'row ->
  Herbier_domain.Merge.decision
(** {!Herbier_domain.Merge.decide} with the table's domain [equal]. *)

val decode_payload :
  ('table, 'row) t -> Yojson.Safe.t -> ('row, Postgrest.Row.error) result
(** An outbox payload (or one PostgREST row) through {!row}, with
    [Codec.decode_value]: never raises. *)

type entry =
  | Entry : ('table, 'row) t * 'row -> entry
      (** An outbox entry's row, typed by its table. *)

type entry_error =
  | Unknown_table of string  (** no synced table has this name *)
  | Bad_payload of string * Postgrest.Row.error
      (** the payload does not decode as the named table's row *)

val decode_entry :
  table_name:string -> Yojson.Safe.t -> (entry, entry_error) result
(** An outbox entry ([table_name], [payload]) through {!of_name} and
    {!decode_payload}. Never raises. *)

val entry_error_to_string : entry_error -> string
(** ["unknown table <name>"], ["<name> payload: <why>"]: the text a parked
    entry's [last_error] carries after ["invalid entry: "]. *)

val id : ('table, 'row) t -> 'row -> string
(** The row's id, canonical lowercase ([Ids.*.to_string]). *)

val updated_at : ('table, 'row) t -> 'row -> Ptime.t

val local : ('table, 'row) t -> string list -> 'row Herbier_store.Stmt.query
(** {!Herbier_store.Stmt.by_ids} over the table ([~json] = [References.json] for
    [reference], [[]] otherwise): the local rows with these ids, any
    [deleted_at], in no particular order. The caller keeps the list at most
    {!Herbier_store.Stmt.max_ids} long. Looking up by id is looking up by
    natural key for the three natural-key tables: their ids are always derived
    from the key ([Ids.*.of_key], architecture §4), on every install, so a row
    with the same key and another id never exists. *)

val write : ('table, 'row) t -> 'row -> Herbier_store.Outbox.bare
(** How a pulled row is stored: [Outbox.without_entry (X.upsert row)] for
    plants, tags, observations, photos (conflict on [id], whole row);
    {!Herbier_store.Tags.upsert_plant_tag},
    {!Herbier_store.References.upsert_plant_ref},
    {!Herbier_store.References.upsert_row} for the three natural-key tables. *)
