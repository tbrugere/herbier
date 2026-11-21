(** Local schema migrations, applied in order by {!Herbier_store_io.Db.open_}
    and recorded in SQLite's [PRAGMA user_version] (0 on a new database).

    A migration is a list of statements, each string exactly one SQL statement
    (multi-line, comments allowed, without a trailing [";"]), run in order in
    one transaction by {!Herbier_store_io.Db.open_} through the plugin's
    [executeSet], which prepares each string as given. No column is named
    [sql_deleted] or [last_modified]: when the database has both columns (in any
    tables), the plugin rewrites every [DELETE] into
    [UPDATE … set sql_deleted = 1]. Checked natively by [test/store].

    Local foreign keys are enforced and cascade on delete, so an upsert is
    [insert … on conflict (id) do update set …], never [insert or replace] or
    [replace into]: those delete the old row first, and the cascade takes its
    children with it. *)

type migration = {version : int; statements : string list}

val migrations : migration list
(** In ascending [version] order, versions [1, 2, …] with no gap. Version 1
    creates the seven synced tables of [Tables] (same names and columns, minus
    the server-only [owner_id] and [observations.loc]), the four lookup tables
    their value columns reference (same names and values as on the server), and
    the local tables [outbox], [sync_state], [settings]. Version 2 creates the
    FTS5 table [plant_search] of {!Search}, the triggers that keep it in sync
    with [plants], [plant_tags], [tags] and [observations], and indexes the
    plants already present. It needs FTS5 in the device's SQLite (the plugin's
    SQLCipher build has it): without it, version 2 fails and
    {!Herbier_store_io.Db.open_} returns [Migration {version = 2; _}]. Version 3
    creates the local lookup table [reference_organs] (values
    [Reference.Organ.all] labels) and the device-only table [ref_images] of
    {!Ref_images}. Version 4 creates the device-only table [commune_packs] of
    {!Commune_packs}. Version 5 creates the device-only table [uploads] of
    {!Uploads}. Version 6 keeps a picked Drive folder in force as the root, its
    picked name becoming [drive_root_folder_name], and deletes the settings rows
    [drive_root_folder_picked] and [drive_root_folder_default]; it reads their
    JSON only through [json_valid]-guarded calls, so a bad value never fails it.
    Version 7 adds [observations.place_detail] (null, and never set without
    [place_derived]: a check, as on the server) and creates the device-only
    table [place_renames] of {!Place_renames}, filled with every live
    observation that has [lat], [lon], a non-blank [place_derived] and a blank
    [place_label] (named before the commune-first rule, renamed once by the
    geocoding pass). Version 8 adds to [place_renames] (keeping its rows) every
    live observation with [lat], [lon], a blank [place_label] and a
    [place_derived] starting with ["Près "]: named before « À <commune> », whose
    source is not stored, renamed once by the same pass. *)

val latest : int
(** Version of the last migration. *)

type error =
  | Unknown_version of {found : int; latest : int}
      (** The database's [user_version] is negative or above {!latest}: written
          by a newer app (downgrade) or by something else. Never migrated. *)

val pending : current:int -> (migration list, error) result
(** [pending ~current] is the migrations with [version > current], in order.
    [Ok []] when [current = latest]; [Error (Unknown_version _)] when
    [current < 0] or [current > latest]. *)

val batch : migration -> string list
(** [m.statements] followed by ["pragma user_version = <m.version>"]: the set of
    one [executeSet] call, so that the plugin's transaction applies the
    statements and the version bump together or not at all. *)
