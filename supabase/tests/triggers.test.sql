-- updated_at is server time on every insert and update, whatever the device
-- sent; created_at is kept as sent; loc follows lat/lon and ignores a client
-- value. Also the observation checks and the natural keys of plant_tags,
-- plant_refs and reference.

begin;
select plan(34);

insert into auth.users (
  instance_id, id, aud, role, email, email_confirmed_at,
  confirmation_token, recovery_token, email_change, email_change_token_new,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000e0001',
  'authenticated', 'authenticated', 'u1@herbier.test', now(), '', '', '', '',
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
);

-- A second row on the natural key of each of plant_tags, plant_refs and
-- reference, inserted below once against live rows and once against
-- tombstones
create temp table nk (what text, stmt text) on commit drop;
insert into nk values
  (
    'plant_tags row for the same plant and tag',
    $$ insert into public.plant_tags (id, plant_id, tag_id, created_at, updated_at)
       values ('00000000-0000-0000-0000-0000000e5102', '00000000-0000-0000-0000-0000000e1101',
               '00000000-0000-0000-0000-0000000e4101', now(), now()) $$
  ),
  (
    'plant_refs row for the same plant and source',
    $$ insert into public.plant_refs (id, plant_id, source, external_id, url, created_at, updated_at)
       values ('00000000-0000-0000-0000-0000000e6102', '00000000-0000-0000-0000-0000000e1101',
               'gbif', '2', 'https://example.org/2', now(), now()) $$
  ),
  (
    'reference row for the same plant and source',
    $$ insert into public.reference (id, plant_id, source, fetched_at, payload, status, created_at, updated_at)
       values ('00000000-0000-0000-0000-0000000e7102', '00000000-0000-0000-0000-0000000e1101',
               'gbif', now(), '{}', 'partial', now(), now()) $$
  );
grant select on nk to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000e0001","role":"authenticated"}', true
);

-- One row per synced table, each sent with a device updated_at of 2000
insert into public.plants (id, display_name, aliases, notes, created_at, updated_at)
values ('00000000-0000-0000-0000-0000000e1101', 'Plante', '{}', '', '2000-01-01', '2000-01-01');
insert into public.observations (id, plant_id, at, lat, lon, created_at, updated_at)
values (
  '00000000-0000-0000-0000-0000000e2101', '00000000-0000-0000-0000-0000000e1101',
  now(), 48, 7, now(), '2000-01-01'
);
insert into public.photos (
  id, observation_id, taken_at, width, height, sha256, preview_path,
  original_target, upload_state, created_at, updated_at
) values (
  '00000000-0000-0000-0000-0000000e3101', '00000000-0000-0000-0000-0000000e2101',
  now(), 4, 3, 'ab', 'p.jpg', 'app_only', 'pending', now(), '2000-01-01'
);
insert into public.tags (id, name, created_at, updated_at)
values ('00000000-0000-0000-0000-0000000e4101', 'arbre', now(), '2000-01-01');
insert into public.plant_tags (id, plant_id, tag_id, created_at, updated_at)
values (
  '00000000-0000-0000-0000-0000000e5101', '00000000-0000-0000-0000-0000000e1101',
  '00000000-0000-0000-0000-0000000e4101', now(), '2000-01-01'
);
insert into public.plant_refs (id, plant_id, source, external_id, url, created_at, updated_at)
values (
  '00000000-0000-0000-0000-0000000e6101', '00000000-0000-0000-0000-0000000e1101',
  'gbif', '1', 'https://example.org', now(), '2000-01-01'
);
insert into public.reference (id, plant_id, source, fetched_at, payload, status, created_at, updated_at)
values (
  '00000000-0000-0000-0000-0000000e7101', '00000000-0000-0000-0000-0000000e1101',
  'gbif', now(), '{"a":1}', 'complete', now(), '2000-01-01'
);

-- Natural keys (the sync merges on them, architecture §4), on live rows
select throws_ok(stmt, '23505', null, 'a second ' || what || ' is rejected') from nk;

select results_eq(
  format('select updated_at from public.%I where id = %L', t, id),
  $$ select now() $$,
  'an insert into ' || t || ' gets server time as updated_at, not the device''s'
)
from (values
  ('plants', '00000000-0000-0000-0000-0000000e1101'),
  ('observations', '00000000-0000-0000-0000-0000000e2101'),
  ('photos', '00000000-0000-0000-0000-0000000e3101'),
  ('tags', '00000000-0000-0000-0000-0000000e4101'),
  ('plant_tags', '00000000-0000-0000-0000-0000000e5101'),
  ('plant_refs', '00000000-0000-0000-0000-0000000e6101'),
  ('reference', '00000000-0000-0000-0000-0000000e7101')
) as v (t, id);

select results_eq(
  format(
    'update public.%I set updated_at = %L, deleted_at = now() where id = %L returning updated_at',
    t, '1999-01-01', id
  ),
  $$ select now() $$,
  'an update of ' || t || ' replaces an explicit updated_at with server time'
)
from (values
  ('plants', '00000000-0000-0000-0000-0000000e1101'),
  ('observations', '00000000-0000-0000-0000-0000000e2101'),
  ('photos', '00000000-0000-0000-0000-0000000e3101'),
  ('tags', '00000000-0000-0000-0000-0000000e4101'),
  ('plant_tags', '00000000-0000-0000-0000-0000000e5101'),
  ('plant_refs', '00000000-0000-0000-0000-0000000e6101'),
  ('reference', '00000000-0000-0000-0000-0000000e7101')
) as v (t, id);

select is(
  (select created_at from public.plants where id = '00000000-0000-0000-0000-0000000e1101'),
  '2000-01-01'::timestamptz,
  'created_at is kept as the device sent it'
);

-- loc
select is(
  (select extensions.st_astext(loc::extensions.geometry) from public.observations
   where id = '00000000-0000-0000-0000-0000000e2101'),
  'POINT(7 48)',
  'loc is set from lon and lat on insert'
);
select is(
  (select extensions.st_srid(loc::extensions.geometry) from public.observations
   where id = '00000000-0000-0000-0000-0000000e2101'),
  4326,
  'loc is in SRID 4326'
);

insert into public.observations (id, plant_id, at, lat, lon, loc, created_at, updated_at)
values (
  '00000000-0000-0000-0000-0000000e2102', '00000000-0000-0000-0000-0000000e1101',
  now(), 48, 7, 'SRID=4326;POINT(0 0)', now(), now()
);
select is(
  (select extensions.st_astext(loc::extensions.geometry) from public.observations
   where id = '00000000-0000-0000-0000-0000000e2102'),
  'POINT(7 48)',
  'a loc sent by the client is replaced by the one from lat and lon'
);

insert into public.observations (id, plant_id, at, lat, lon, created_at, updated_at)
values (
  '00000000-0000-0000-0000-0000000e2103', '00000000-0000-0000-0000-0000000e1101',
  now(), null, null, now(), now()
);
select ok(
  (select loc is null from public.observations where id = '00000000-0000-0000-0000-0000000e2103'),
  'an observation without a position has no loc'
);

update public.observations set lat = 45, lon = 5
where id = '00000000-0000-0000-0000-0000000e2101';
select is(
  (select extensions.st_astext(loc::extensions.geometry) from public.observations
   where id = '00000000-0000-0000-0000-0000000e2101'),
  'POINT(5 45)',
  'loc follows an update of lat and lon'
);

update public.observations set lat = null, lon = null, accuracy_m = null
where id = '00000000-0000-0000-0000-0000000e2101';
select ok(
  (select loc is null from public.observations where id = '00000000-0000-0000-0000-0000000e2101'),
  'removing the position clears loc'
);

-- Observation checks. The loc trigger runs before them and PostGIS notices
-- the out-of-range points it is given; the notices are noise here.
set local client_min_messages = warning;
select throws_ok(
  format(
    'insert into public.observations (id, at, lat, lon, accuracy_m, created_at, updated_at)'
    ' values (%L, now(), %s, %s, %s, now(), now())',
    '00000000-0000-0000-0000-0000000e2104', lat, lon, acc
  ),
  '23514', null,
  'an observation with ' || what || ' is rejected'
)
from (values
  ('lat without lon', '48', 'null', 'null'),
  ('accuracy_m without position', 'null', 'null', '5'),
  ('lat 91', '91', '7', 'null'),
  ('lon 181', '48', '181', 'null'),
  ('a negative accuracy_m', '48', '7', '-1')
) as v (what, lat, lon, acc);

-- A place_detail qualifies a derived name: never one without it.
select throws_ok(
  $$ insert into public.observations (id, at, lat, lon, place_detail, created_at, updated_at)
     values ('00000000-0000-0000-0000-0000000e2105', now(), 48, 7, 'Pélégri', now(), now()) $$,
  '23514', null,
  'an observation with a place_detail and no place_derived is rejected'
);
select lives_ok(
  $$ insert into public.observations (
       id, at, lat, lon, place_derived, place_detail, created_at, updated_at
     ) values (
       '00000000-0000-0000-0000-0000000e2106', now(), 48, 7,
       'Près de Lissac-et-Mouret', 'Pélégri', now(), now()
     ) $$,
  'an observation with a place_derived and a place_detail is accepted'
);

-- The update loop above soft-deleted every row: the natural keys still hold
-- on tombstones, so re-adding a link revives its row (architecture §2)
select throws_ok(
  stmt, '23505', null, 'a second ' || what || ' is rejected, even when the first is soft-deleted'
)
from nk;

select * from finish();
rollback;
