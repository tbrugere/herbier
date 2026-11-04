-- The synced tables of architecture §4, with their RLS policies, triggers and
-- the plants_near RPC. Written by hand (layout §5: never `db diff`); the
-- per-object dump in supabase/schema/ is regenerated from it.
-- Ids and created_at come from the device, so neither has a default;
-- updated_at is sent too but replaced by server time on every write (the
-- pull cursor); owner_id defaults to the caller and is never sent by the app.

-- Extensions
create extension if not exists postgis with schema extensions;

-- Lookup tables (docs/stack.md: never Postgres enum types). Values =
-- the to_string of the OCaml module named in each comment (architecture §2).
create table public.reference_sources (
  value text primary key,
  description text
);
comment on table public.reference_sources is
  'Where a plant reference or a reference payload comes from.
metadata: kind=lookup, ocaml=Reference.Source';
insert into public.reference_sources (value, description) values
  ('gbif', 'GBIF backbone taxonomy'),
  ('wikidata', 'Wikidata'),
  ('wikipedia', 'Wikipedia'),
  ('powo', 'Plants of the World Online'),
  ('ipni', 'International Plant Names Index'),
  ('taxref', 'TAXREF (INPN)'),
  ('tela', 'Tela Botanica'),
  ('eppo', 'EPPO Global Database'),
  ('inat', 'iNaturalist'),
  ('plantnet', 'Pl@ntNet');

create table public.reference_statuses (
  value text primary key,
  description text
);
comment on table public.reference_statuses is
  'How complete a fetched reference payload is.
metadata: kind=lookup, ocaml=Reference.Status';
insert into public.reference_statuses (value, description) values
  ('complete', 'every expected field was fetched'),
  ('partial', 'some fields are missing'),
  ('missing', 'the source has no entry'),
  ('failed', 'the fetch failed');

create table public.photo_original_targets (
  value text primary key,
  description text
);
comment on table public.photo_original_targets is
  'Where the original of a photo is kept.
metadata: kind=lookup, ocaml=Photo.Original_target';
insert into public.photo_original_targets (value, description) values
  ('app_only', 'only on the device'),
  ('drive', 'uploaded to Google Drive');

create table public.photo_upload_states (
  value text primary key,
  description text
);
comment on table public.photo_upload_states is
  'Upload state of a photo original.
metadata: kind=lookup, ocaml=Photo.Upload_state';
insert into public.photo_upload_states (value, description) values
  ('pending', 'waiting for upload'),
  ('uploaded', 'uploaded to its target'),
  ('failed', 'the last upload failed'),
  ('original_missing', 'the original is gone from its target; the preview is kept');

-- Tables (hard deletes only happen on account deletion; the app soft-deletes)
create table public.plants (
  id uuid primary key,
  owner_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  display_name text not null,
  aliases text[] not null,
  scientific_name text,
  authorship text,
  gbif_key integer,
  notes text not null,
  notes_updated_at timestamptz,
  cover_photo_id uuid,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz
);

create table public.observations (
  id uuid primary key,
  owner_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  plant_id uuid constraint observations_plant_id_fkey references public.plants (id) on delete cascade,
  at timestamptz not null,
  lat double precision,
  lon double precision,
  accuracy_m double precision,
  place_label text,
  place_derived text,
  note text,
  loc extensions.geography(Point, 4326),
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  constraint observations_position_both_or_neither check ((lat is null) = (lon is null)),
  constraint observations_accuracy_needs_position check (accuracy_m is null or lat is not null),
  constraint observations_lat_range check (lat between -90 and 90),
  constraint observations_lon_range check (lon between -180 and 180),
  constraint observations_accuracy_nonnegative check (accuracy_m >= 0)
);

create table public.photos (
  id uuid primary key,
  owner_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  observation_id uuid not null constraint photos_observation_id_fkey references public.observations (id) on delete cascade,
  taken_at timestamptz not null,
  width integer not null,
  height integer not null,
  sha256 text not null,
  preview_path text not null,
  preview_bucket_key text,
  original_target text not null references public.photo_original_targets (value),
  drive_file_id text,
  upload_state text not null references public.photo_upload_states (value),
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz
);

alter table public.plants
  add constraint plants_cover_photo_id_fkey
  foreign key (cover_photo_id) references public.photos (id) on delete set null;

create table public.tags (
  id uuid primary key,
  owner_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name text not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz
);

create table public.plant_tags (
  id uuid primary key,
  owner_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  plant_id uuid not null constraint plant_tags_plant_id_fkey references public.plants (id) on delete cascade,
  tag_id uuid not null constraint plant_tags_tag_id_fkey references public.tags (id) on delete cascade,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  constraint plant_tags_plant_id_tag_id_key unique (plant_id, tag_id)
);

create table public.plant_refs (
  id uuid primary key,
  owner_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  plant_id uuid not null constraint plant_refs_plant_id_fkey references public.plants (id) on delete cascade,
  source text not null references public.reference_sources (value),
  external_id text not null,
  url text not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  constraint plant_refs_plant_id_source_key unique (plant_id, source)
);

create table public.reference (
  id uuid primary key,
  owner_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  plant_id uuid not null constraint reference_plant_id_fkey references public.plants (id) on delete cascade,
  source text not null references public.reference_sources (value),
  fetched_at timestamptz not null,
  payload jsonb not null,
  status text not null references public.reference_statuses (value),
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  constraint reference_plant_id_source_key unique (plant_id, source)
);

-- Comments: the `metadata:` line is read by postgrest-codegen, which
-- generates app/store/tables.ml (docs/stack.md). id= names the Herbier_domain
-- module typing the table's uuid primary key and every foreign key to it;
-- server_only columns are absent from tables.ml; no_reverse drops the
-- relationship from the referenced table back to this column's table (a
-- photo has no use for the plants it is the cover of).
comment on table public.plants is
  'A plant of the collection.
metadata: id=Ids.Plant_id';
comment on table public.observations is
  'One sighting, optionally of a plant, with its position.
metadata: id=Ids.Observation_id';
comment on table public.photos is
  'A photo of an observation: the preview and where its original is kept.
metadata: id=Ids.Photo_id';
comment on table public.tags is
  'A user-defined tag.
metadata: id=Ids.Tag_id';
comment on table public.plant_tags is
  'A tag on a plant.
metadata: id=Ids.Plant_tag_id';
comment on table public.plant_refs is
  'The plant''s identifier at one external source.
metadata: id=Ids.Plant_ref_id';
comment on table public.reference is
  'What one external source said about a plant.
metadata: id=Ids.Reference_id';
comment on column public.plants.owner_id is 'metadata: server_only';
comment on column public.observations.owner_id is 'metadata: server_only';
comment on column public.photos.owner_id is 'metadata: server_only';
comment on column public.tags.owner_id is 'metadata: server_only';
comment on column public.plant_tags.owner_id is 'metadata: server_only';
comment on column public.plant_refs.owner_id is 'metadata: server_only';
comment on column public.reference.owner_id is 'metadata: server_only';
comment on column public.observations.loc is
  'Set from lat and lon by a trigger.
metadata: server_only';
comment on column public.plants.cover_photo_id is
  'The photo shown on the plant''s card.
metadata: no_reverse';

-- Indexes (owner_id leads: the RLS predicate and the pull query on updated_at)
create index plants_owner_id_updated_at_idx on public.plants (owner_id, updated_at);
create index observations_owner_id_updated_at_idx on public.observations (owner_id, updated_at);
create index photos_owner_id_updated_at_idx on public.photos (owner_id, updated_at);
create index tags_owner_id_updated_at_idx on public.tags (owner_id, updated_at);
create index plant_tags_owner_id_updated_at_idx on public.plant_tags (owner_id, updated_at);
create index plant_refs_owner_id_updated_at_idx on public.plant_refs (owner_id, updated_at);
create index reference_owner_id_updated_at_idx on public.reference (owner_id, updated_at);
create index observations_plant_id_idx on public.observations (plant_id);
create index photos_observation_id_idx on public.photos (observation_id);
create index plant_tags_tag_id_idx on public.plant_tags (tag_id);
create index plants_cover_photo_id_idx on public.plants (cover_photo_id);
create index observations_loc_idx on public.observations using gist (loc);

-- Trigger: updated_at is server time on every insert and update, so the
-- pull cursor never depends on a device clock and a row created offline and
-- pushed late is still pulled by the other installs
create function public.set_updated_at ()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
revoke execute on function public.set_updated_at () from public, anon, authenticated;
create trigger plants_set_updated_at before insert or update on public.plants
  for each row execute function public.set_updated_at ();
create trigger observations_set_updated_at before insert or update on public.observations
  for each row execute function public.set_updated_at ();
create trigger photos_set_updated_at before insert or update on public.photos
  for each row execute function public.set_updated_at ();
create trigger tags_set_updated_at before insert or update on public.tags
  for each row execute function public.set_updated_at ();
create trigger plant_tags_set_updated_at before insert or update on public.plant_tags
  for each row execute function public.set_updated_at ();
create trigger plant_refs_set_updated_at before insert or update on public.plant_refs
  for each row execute function public.set_updated_at ();
create trigger reference_set_updated_at before insert or update on public.reference
  for each row execute function public.set_updated_at ();

-- Trigger: loc is derived from lat/lon on every write, so a client-written
-- loc never survives
create function public.observations_set_loc ()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.loc := case
    when new.lat is null then null
    else extensions.st_setsrid(extensions.st_makepoint(new.lon, new.lat), 4326)::extensions.geography
  end;
  return new;
end;
$$;
revoke execute on function public.observations_set_loc () from public, anon, authenticated;
create trigger observations_set_loc before insert or update on public.observations
  for each row execute function public.observations_set_loc ();

-- Row-level security and grants: owner-only, authenticated role only;
-- lookup tables are read-only
alter table public.reference_sources enable row level security;
create policy reference_sources_select on public.reference_sources for select to authenticated using (true);
revoke all on table public.reference_sources from anon, authenticated;
grant select on table public.reference_sources to authenticated;

alter table public.reference_statuses enable row level security;
create policy reference_statuses_select on public.reference_statuses for select to authenticated using (true);
revoke all on table public.reference_statuses from anon, authenticated;
grant select on table public.reference_statuses to authenticated;

alter table public.photo_original_targets enable row level security;
create policy photo_original_targets_select on public.photo_original_targets for select to authenticated using (true);
revoke all on table public.photo_original_targets from anon, authenticated;
grant select on table public.photo_original_targets to authenticated;

alter table public.photo_upload_states enable row level security;
create policy photo_upload_states_select on public.photo_upload_states for select to authenticated using (true);
revoke all on table public.photo_upload_states from anon, authenticated;
grant select on table public.photo_upload_states to authenticated;

alter table public.plants enable row level security;
create policy plants_select_own on public.plants for select to authenticated
  using ((select auth.uid()) = owner_id);
create policy plants_insert_own on public.plants for insert to authenticated
  with check ((select auth.uid()) = owner_id);
create policy plants_update_own on public.plants for update to authenticated
  using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id);
create policy plants_delete_own on public.plants for delete to authenticated
  using ((select auth.uid()) = owner_id);
revoke all on table public.plants from anon, authenticated;
grant select, insert, update, delete on table public.plants to authenticated;

alter table public.observations enable row level security;
create policy observations_select_own on public.observations for select to authenticated
  using ((select auth.uid()) = owner_id);
create policy observations_insert_own on public.observations for insert to authenticated
  with check ((select auth.uid()) = owner_id);
create policy observations_update_own on public.observations for update to authenticated
  using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id);
create policy observations_delete_own on public.observations for delete to authenticated
  using ((select auth.uid()) = owner_id);
revoke all on table public.observations from anon, authenticated;
grant select, insert, update, delete on table public.observations to authenticated;

alter table public.photos enable row level security;
create policy photos_select_own on public.photos for select to authenticated
  using ((select auth.uid()) = owner_id);
create policy photos_insert_own on public.photos for insert to authenticated
  with check ((select auth.uid()) = owner_id);
create policy photos_update_own on public.photos for update to authenticated
  using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id);
create policy photos_delete_own on public.photos for delete to authenticated
  using ((select auth.uid()) = owner_id);
revoke all on table public.photos from anon, authenticated;
grant select, insert, update, delete on table public.photos to authenticated;

alter table public.tags enable row level security;
create policy tags_select_own on public.tags for select to authenticated
  using ((select auth.uid()) = owner_id);
create policy tags_insert_own on public.tags for insert to authenticated
  with check ((select auth.uid()) = owner_id);
create policy tags_update_own on public.tags for update to authenticated
  using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id);
create policy tags_delete_own on public.tags for delete to authenticated
  using ((select auth.uid()) = owner_id);
revoke all on table public.tags from anon, authenticated;
grant select, insert, update, delete on table public.tags to authenticated;

alter table public.plant_tags enable row level security;
create policy plant_tags_select_own on public.plant_tags for select to authenticated
  using ((select auth.uid()) = owner_id);
create policy plant_tags_insert_own on public.plant_tags for insert to authenticated
  with check ((select auth.uid()) = owner_id);
create policy plant_tags_update_own on public.plant_tags for update to authenticated
  using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id);
create policy plant_tags_delete_own on public.plant_tags for delete to authenticated
  using ((select auth.uid()) = owner_id);
revoke all on table public.plant_tags from anon, authenticated;
grant select, insert, update, delete on table public.plant_tags to authenticated;

alter table public.plant_refs enable row level security;
create policy plant_refs_select_own on public.plant_refs for select to authenticated
  using ((select auth.uid()) = owner_id);
create policy plant_refs_insert_own on public.plant_refs for insert to authenticated
  with check ((select auth.uid()) = owner_id);
create policy plant_refs_update_own on public.plant_refs for update to authenticated
  using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id);
create policy plant_refs_delete_own on public.plant_refs for delete to authenticated
  using ((select auth.uid()) = owner_id);
revoke all on table public.plant_refs from anon, authenticated;
grant select, insert, update, delete on table public.plant_refs to authenticated;

alter table public.reference enable row level security;
create policy reference_select_own on public.reference for select to authenticated
  using ((select auth.uid()) = owner_id);
create policy reference_insert_own on public.reference for insert to authenticated
  with check ((select auth.uid()) = owner_id);
create policy reference_update_own on public.reference for update to authenticated
  using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id);
create policy reference_delete_own on public.reference for delete to authenticated
  using ((select auth.uid()) = owner_id);
revoke all on table public.reference from anon, authenticated;
grant select, insert, update, delete on table public.reference to authenticated;

-- RPC plants_near: live plants with an observation within radius_m of pt.
-- Security invoker, so RLS restricts both tables to the caller's rows.
-- PostgREST callers pass pt as EWKT text ('SRID=4326;POINT(lon lat)').
create function public.plants_near (pt extensions.geography, radius_m double precision)
returns setof public.plants
language sql
stable
security invoker
set search_path = ''
as $$
  select p.* from public.plants p
  where p.deleted_at is null
    and exists (
      select 1 from public.observations o
      where o.plant_id = p.id and o.deleted_at is null
        and extensions.st_dwithin(o.loc, pt, radius_m))
$$;
revoke execute on function public.plants_near (extensions.geography, double precision) from public, anon;
grant execute on function public.plants_near (extensions.geography, double precision) to authenticated;
