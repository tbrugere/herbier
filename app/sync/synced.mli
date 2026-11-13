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
