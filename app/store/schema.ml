type migration = {version : int; statements : string list}

(* Migration 1: the local mirror of the synced tables (store/tables.ml, same
   names and columns, without the server-only owner_id and observations.loc),
   plus the local-only outbox, sync_state and settings.
   Types: uuid, lookup values and text are text. timestamptz is text in the
   fixed-width UTC format of Codec.timestamp, so text order is time order.
   text[] and jsonb are text holding JSON. double precision is real.
   Foreign keys mirror the server except plants.cover_photo_id, which would
   close a cycle with photos and break a first pull. Closed value sets are
   lookup tables, as on the server (docs/stack.md), with the same values; a
   value added later is a new migration inserting its row. Text primary keys
   say not null: SQLite would otherwise accept a null one. *)
let v1 =
  [
    {|create table reference_sources (value text primary key not null)|};
    {|insert into reference_sources (value) values
  ('gbif'), ('wikidata'), ('wikipedia'), ('powo'), ('ipni'),
  ('taxref'), ('tela'), ('eppo'), ('inat'), ('plantnet')|};
    {|create table reference_statuses (value text primary key not null)|};
    {|insert into reference_statuses (value) values ('complete'), ('partial'), ('missing'), ('failed')|};
    {|create table photo_original_targets (value text primary key not null)|};
    {|insert into photo_original_targets (value) values ('app_only'), ('drive')|};
    {|create table photo_upload_states (value text primary key not null)|};
    {|insert into photo_upload_states (value) values ('pending'), ('uploaded'), ('failed'), ('original_missing')|};
    {|create table plants (
  id text primary key not null,
  display_name text not null,
  aliases text not null,
  scientific_name text,
  authorship text,
  gbif_key integer,
  notes text not null,
  notes_updated_at text,
  cover_photo_id text,
  created_at text not null,
  updated_at text not null,
  deleted_at text
)|};
    {|create table observations (
  id text primary key not null,
  plant_id text references plants (id) on delete cascade,
  at text not null,
  lat real,
  lon real,
  accuracy_m real,
  place_label text,
  place_derived text,
  note text,
  created_at text not null,
  updated_at text not null,
  deleted_at text,
  constraint observations_position_both_or_neither check ((lat is null) = (lon is null)),
  constraint observations_accuracy_needs_position check (accuracy_m is null or lat is not null),
  constraint observations_lat_range check (lat between -90 and 90),
  constraint observations_lon_range check (lon between -180 and 180),
  constraint observations_accuracy_nonnegative check (accuracy_m >= 0)
)|};
    {|create table photos (
  id text primary key not null,
  observation_id text not null references observations (id) on delete cascade,
  taken_at text not null,
  width integer not null,
  height integer not null,
  sha256 text not null,
  preview_path text not null,
  preview_bucket_key text,
  original_target text not null references photo_original_targets (value),
  drive_file_id text,
  upload_state text not null references photo_upload_states (value),
  created_at text not null,
  updated_at text not null,
  deleted_at text
)|};
    {|create table tags (
  id text primary key not null,
  name text not null,
  created_at text not null,
  updated_at text not null,
  deleted_at text
)|};
    {|create table plant_tags (
  id text primary key not null,
  plant_id text not null references plants (id) on delete cascade,
  tag_id text not null references tags (id) on delete cascade,
  created_at text not null,
  updated_at text not null,
  deleted_at text,
  constraint plant_tags_plant_id_tag_id_key unique (plant_id, tag_id)
)|};
    {|create table plant_refs (
  id text primary key not null,
  plant_id text not null references plants (id) on delete cascade,
  source text not null references reference_sources (value),
  external_id text not null,
  url text not null,
  created_at text not null,
  updated_at text not null,
  deleted_at text,
  constraint plant_refs_plant_id_source_key unique (plant_id, source)
)|};
    {|create table reference (
  id text primary key not null,
  plant_id text not null references plants (id) on delete cascade,
  source text not null references reference_sources (value),
  fetched_at text not null,
  payload text not null,
  status text not null references reference_statuses (value),
  created_at text not null,
  updated_at text not null,
  deleted_at text,
  constraint reference_plant_id_source_key unique (plant_id, source)
)|};
    {|create table outbox (
  seq integer primary key,
  table_name text not null,
  row_id text not null,
  op text not null,
  payload_json text not null,
  created_at text not null,
  attempts integer not null default 0,
  last_error text
)|};
    {|create table sync_state (
  table_name text primary key not null,
  last_pulled_at text not null
)|};
    {|create table settings (
  key text primary key not null,
  value text not null
)|};
    {|create index observations_plant_id_idx on observations (plant_id)|};
    {|create index photos_observation_id_idx on photos (observation_id)|};
    {|create index plant_tags_tag_id_idx on plant_tags (tag_id)|};
    {|create index plants_cover_photo_id_idx on plants (cover_photo_id)|};
  ]

(* Migration 2: the FTS5 index of Search (architecture §3). One document per
   live plant, keyed by the plant's id in the unindexed plant_id column (not by
   rowid: plants have no INTEGER PRIMARY KEY, so a VACUUM, a re-key or a table
   rebuild may renumber their rowids). Triggers keep it in sync for every
   writer (UI, seed, pulls, cascades); each one rebuilds the documents of the
   plants its row touches.

   The helpers below are frozen with migration 2: a database at version 2
   holds the triggers they built. A later migration copies them, never edits
   them. *)

let names =
  "p.display_name || ' ' || coalesce(p.scientific_name, '') || ' ' || \
   coalesce((select group_concat(j.value, ' ') from \
   json_each(iif(json_valid(p.aliases), p.aliases, '[]')) j where j.type = \
   'text'), '')"

let tags =
  "coalesce((select group_concat(t.name, ' ') from plant_tags pt join tags t \
   on t.id = pt.tag_id where pt.plant_id = p.id and pt.deleted_at is null and \
   t.deleted_at is null), '')"

let places =
  "coalesce((select group_concat(coalesce(o.place_label, '') || ' ' || \
   coalesce(o.place_derived, ''), ' ') from observations o where o.plant_id = \
   p.id and o.deleted_at is null), '')"

let documents where =
  Printf.sprintf
    "insert into plant_search (plant_id, names, tags, places)\n\
    \    select p.id,\n\
    \      %s,\n\
    \      %s,\n\
    \      %s\n\
    \    from plants p\n\
    \    where %s"
    names tags places where

(* The statements of a trigger body that rebuild the documents of the plants
   matching [cond]. *)
let reindex cond =
  [
    Printf.sprintf
      "delete from plant_search\n\
      \    where plant_id in (select p.id from plants p where %s)"
      cond;
    documents (Printf.sprintf "(%s) and p.deleted_at is null" cond);
  ]

let trigger ~name ~event ~table body =
  Printf.sprintf "create trigger %s after %s on %s for each row\nbegin\n%send"
    name event table
    (String.concat "" (List.map (fun s -> "  " ^ s ^ ";\n") body))

let v2 =
  [
    "create virtual table plant_search using fts5(\n\
    \  plant_id unindexed, names, tags, places,\n\
    \  tokenize = 'unicode61 remove_diacritics 2'\n\
     )";
    trigger ~name:"plants_search_ai" ~event:"insert" ~table:"plants"
      (reindex "p.id = new.id");
    trigger ~name:"plants_search_au" ~event:"update" ~table:"plants"
      (reindex "p.id in (old.id, new.id)");
    trigger ~name:"plants_search_ad" ~event:"delete" ~table:"plants"
      ["delete from plant_search where plant_id = old.id"];
    trigger ~name:"plant_tags_search_ai" ~event:"insert" ~table:"plant_tags"
      (reindex "p.id = new.plant_id");
    trigger ~name:"plant_tags_search_au" ~event:"update" ~table:"plant_tags"
      (reindex "p.id in (old.plant_id, new.plant_id)");
    trigger ~name:"plant_tags_search_ad" ~event:"delete" ~table:"plant_tags"
      (reindex "p.id = old.plant_id");
    (* A hard tag delete cascades to plant_tags, whose delete trigger then
       fires: no tags_search_ad needed. *)
    trigger ~name:"tags_search_au" ~event:"update" ~table:"tags"
      (reindex "p.id in (select plant_id from plant_tags where tag_id = new.id)");
    trigger ~name:"observations_search_ai" ~event:"insert" ~table:"observations"
      (reindex "p.id = new.plant_id");
    trigger ~name:"observations_search_au" ~event:"update" ~table:"observations"
      (reindex "p.id in (old.plant_id, new.plant_id)");
    trigger ~name:"observations_search_ad" ~event:"delete" ~table:"observations"
      (reindex "p.id = old.plant_id");
    (* Indexes the plants already present. *)
    documents "p.deleted_at is null";
  ]

(* Migration 3: the device-only organ photos of 4f (Ref_images, architecture
   §2 RefImage, §6). Never synced, so no server table mirrors it; its organ
   column is a local lookup table like the four of migration 1. *)
let v3 =
  [
    {|create table reference_organs (value text primary key not null)|};
    {|insert into reference_organs (value) values ('flower'), ('leaf'), ('fruit'), ('habit')|};
    {|create table ref_images (
  plant_id text not null references plants (id) on delete cascade,
  source text not null references reference_sources (value),
  organ text not null references reference_organs (value),
  remote_url text not null,
  licence text not null,
  attribution text not null,
  thumb_path text,
  primary key (plant_id, source, organ)
)|};
  ]

(* Migration 4: the device-only commune packs of « IGN hors-ligne »
   (Commune_packs, architecture §3, §8). Never synced: re-downloadable from
   the Géoplateforme. *)
let v4 =
  [
    {|create table commune_packs (
  departement text primary key not null,
  name text not null check (length(trim(name)) > 0),
  path text not null unique,
  size_bytes integer not null check (size_bytes >= 0),
  communes integer not null check (communes > 0),
  downloaded_at text not null
)|};
  ]

(* Migration 5: the device-only queue of originals bound for Drive
   (Uploads, architecture §3, §5). Never synced: only the install that holds
   an original uploads it. *)
let v5 =
  [
    {|create table uploads (
  photo_id text primary key not null references photos (id) on delete cascade,
  path text not null,
  mime text not null,
  size_bytes integer not null check (size_bytes >= 0),
  session_url text,
  session_created_at text,
  attempts integer not null default 0 check (attempts >= 0),
  last_error text,
  created_at text not null,
  check ((session_url is null) = (session_created_at is null))
)|};
  ]

let migrations =
  [
    {version = 1; statements = v1};
    {version = 2; statements = v2};
    {version = 3; statements = v3};
    {version = 4; statements = v4};
    {version = 5; statements = v5};
  ]

let latest = match List.rev migrations with m :: _ -> m.version | [] -> 0

type error = Unknown_version of {found : int; latest : int}

let pending ~current =
  match current with
  | found when found < 0 || found > latest ->
      Error (Unknown_version {found; latest})
  | _ -> Ok (List.filter (fun m -> m.version > current) migrations)

let batch m =
  m.statements @ [Printf.sprintf "pragma user_version = %d" m.version]
