-- Owner-only reads and writes on every synced table, the push upsert shape
-- (insert ... on conflict (id) do update, what PostgREST sends for
-- on_conflict=id with merge-duplicates), read-only lookup tables and their
-- foreign keys. Per-table checks are generated from the fx table below:
-- one row per synced table, its two owners' rows and its non-key columns.

begin;
select plan(127);

-- Fixture users U1 (...e0001) and U2 (...e0002), as postgres
insert into auth.users (
  instance_id, id, aud, role, email, email_confirmed_at,
  confirmation_token, recovery_token, email_change, email_change_token_new,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    '00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000e0001',
    'authenticated', 'authenticated', 'u1@herbier.test', now(), '', '', '', '',
    '{"provider":"email","providers":["email"]}', '{}', now(), now()
  ),
  (
    '00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000e0002',
    'authenticated', 'authenticated', 'u2@herbier.test', now(), '', '', '', '',
    '{"provider":"email","providers":["email"]}', '{}', now(), now()
  );

-- Row ids end in e<table><owner><n>: table 1 plants, 2 observations,
-- 3 photos, 4 tags, 5 plant_tags, 6 plant_refs, 7 reference. ord is that
-- table number, parents before children, so the hard deletes at the end run
-- in reverse (a parent first would take its child along by cascade, and the
-- child's delete would find nothing). id1 is U1's row,
-- id2 U2's, foreign_id the row U2 tries to create in U1's name. vals1/vals2
-- fill cols with each owner's parents; created_at and updated_at are added
-- by the generated statements.
create temp table fx (
  ord int, t text, id1 uuid, id2 uuid, foreign_id uuid, cols text, vals1 text, vals2 text
) on commit drop;
insert into fx values
  (
    1, 'plants',
    '00000000-0000-0000-0000-0000000e1101', '00000000-0000-0000-0000-0000000e1201',
    '00000000-0000-0000-0000-0000000e1202',
    'display_name, aliases, notes',
    $$'Plante', '{}', ''$$,
    $$'Plante', '{}', ''$$
  ),
  (
    2, 'observations',
    '00000000-0000-0000-0000-0000000e2101', '00000000-0000-0000-0000-0000000e2201',
    '00000000-0000-0000-0000-0000000e2202',
    'plant_id, at, lat, lon',
    $$'00000000-0000-0000-0000-0000000e1101', now(), 48, 7$$,
    $$'00000000-0000-0000-0000-0000000e1201', now(), 48, 7$$
  ),
  (
    3, 'photos',
    '00000000-0000-0000-0000-0000000e3101', '00000000-0000-0000-0000-0000000e3201',
    '00000000-0000-0000-0000-0000000e3202',
    'observation_id, taken_at, width, height, sha256, preview_path, original_target, upload_state',
    $$'00000000-0000-0000-0000-0000000e2101', now(), 4, 3, 'ab', 'p.jpg', 'app_only', 'pending'$$,
    $$'00000000-0000-0000-0000-0000000e2201', now(), 4, 3, 'ab', 'p.jpg', 'app_only', 'pending'$$
  ),
  (
    4, 'tags',
    '00000000-0000-0000-0000-0000000e4101', '00000000-0000-0000-0000-0000000e4201',
    '00000000-0000-0000-0000-0000000e4202',
    'name',
    $$'arbre'$$,
    $$'arbre'$$
  ),
  (
    5, 'plant_tags',
    '00000000-0000-0000-0000-0000000e5101', '00000000-0000-0000-0000-0000000e5201',
    '00000000-0000-0000-0000-0000000e5202',
    'plant_id, tag_id',
    $$'00000000-0000-0000-0000-0000000e1101', '00000000-0000-0000-0000-0000000e4101'$$,
    $$'00000000-0000-0000-0000-0000000e1201', '00000000-0000-0000-0000-0000000e4201'$$
  ),
  (
    6, 'plant_refs',
    '00000000-0000-0000-0000-0000000e6101', '00000000-0000-0000-0000-0000000e6201',
    '00000000-0000-0000-0000-0000000e6202',
    'plant_id, source, external_id, url',
    $$'00000000-0000-0000-0000-0000000e1101', 'gbif', '1', 'https://example.org'$$,
    $$'00000000-0000-0000-0000-0000000e1201', 'gbif', '1', 'https://example.org'$$
  ),
  (
    7, 'reference',
    '00000000-0000-0000-0000-0000000e7101', '00000000-0000-0000-0000-0000000e7201',
    '00000000-0000-0000-0000-0000000e7202',
    'plant_id, source, fetched_at, payload, status',
    $$'00000000-0000-0000-0000-0000000e1101', 'gbif', now(), '{"a":1}', 'complete'$$,
    $$'00000000-0000-0000-0000-0000000e1201', 'gbif', now(), '{"a":1}', 'complete'$$
  );
grant select on fx to authenticated;

-- The lookup values as the table owner sees them, compared below with what
-- authenticated reads (no value list or count written here)
create temp table lk on commit drop as
  select 'reference_sources' as t, value from public.reference_sources
  union all select 'reference_statuses', value from public.reference_statuses
  union all select 'photo_original_targets', value from public.photo_original_targets
  union all select 'photo_upload_states', value from public.photo_upload_states;
grant select on lk to authenticated;

-- Each user creates one row per table, owner_id left to its default
set local role authenticated;
select set_config(
  'request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000e0001","role":"authenticated"}', true
);
select lives_ok(
  format(
    'insert into public.%I (id, %s, created_at, updated_at) values (%L, %s, %L, now())',
    t, cols, id1, vals1, '2000-01-01'
  ),
  'U1 inserts its ' || t || ' row without owner_id'
)
from fx;

select set_config(
  'request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000e0002","role":"authenticated"}', true
);
select lives_ok(
  format(
    'insert into public.%I (id, %s, created_at, updated_at) values (%L, %s, %L, now())',
    t, cols, id2, vals2, '2000-01-01'
  ),
  'U2 inserts its ' || t || ' row without owner_id'
)
from fx;

reset role;
select results_eq(
  format('select owner_id from public.%I where id = %L', t, id1),
  $$ values ('00000000-0000-0000-0000-0000000e0001'::uuid) $$,
  t || '.owner_id defaults to the inserting user'
)
from fx;

set local role authenticated;
select set_config(
  'request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000e0001","role":"authenticated"}', true
);
select results_eq(
  format('select id from public.%I', t),
  format('values (%L::uuid)', id1),
  'U1 sees its own ' || t || ' row and nothing else'
)
from fx;

-- U2 against U1's rows
select set_config(
  'request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000e0002","role":"authenticated"}', true
);
select is_empty(
  format('select 1 from public.%I where id = %L', t, id1),
  'U2 does not see U1''s ' || t || ' row'
)
from fx;
select is_empty(
  format('update public.%I set updated_at = now() where id = %L returning id', t, id1),
  'U2 updates none of U1''s ' || t || ' rows'
)
from fx;
select is_empty(
  format('delete from public.%I where id = %L returning id', t, id1),
  'U2 deletes none of U1''s ' || t || ' rows'
)
from fx;
select throws_ok(
  format(
    'insert into public.%I (id, owner_id, %s, created_at, updated_at) values (%L, %L, %s, now(), now())',
    t, cols, foreign_id, '00000000-0000-0000-0000-0000000e0001', vals2
  ),
  '42501', null,
  'U2 cannot insert a ' || t || ' row owned by U1'
)
from fx;
select throws_ok(
  format(
    'insert into public.%I (id, %s, created_at, updated_at) values (%L, %s, %L, now())'
    ' on conflict (id) do update set created_at = excluded.created_at',
    t, cols, id1, vals2, '2001-02-03'
  ),
  '42501', null,
  'U2''s push upsert onto U1''s ' || t || ' id is rejected'
)
from fx;
-- Accepted, architecture §4: foreign keys skip RLS
select lives_ok(
  $$ insert into public.observations (id, plant_id, at, created_at, updated_at)
     values ('00000000-0000-0000-0000-0000000e2203', '00000000-0000-0000-0000-0000000e1101',
             now(), now(), now()) $$,
  'U2 can attach an observation to U1''s plant (foreign keys skip RLS, accepted)'
);

reset role;
select results_eq(
  format('select owner_id, created_at from public.%I where id = %L', t, id1),
  $$ values ('00000000-0000-0000-0000-0000000e0001'::uuid, '2000-01-01'::timestamptz) $$,
  'U1''s ' || t || ' row is still there, unchanged, after U2''s attempts'
)
from fx;

-- U1 on its own rows
set local role authenticated;
select set_config(
  'request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000e0001","role":"authenticated"}', true
);
select throws_ok(
  format(
    'update public.%I set owner_id = %L where id = %L',
    t, '00000000-0000-0000-0000-0000000e0002', id1
  ),
  '42501', null,
  'U1 cannot give its ' || t || ' row to U2'
)
from fx;
select lives_ok(
  format(
    'insert into public.%I (id, %s, created_at, updated_at) values (%L, %s, %L, now())'
    ' on conflict (id) do update set created_at = excluded.created_at',
    t, cols, id1, vals1, '2001-02-03'
  ),
  'U1''s push upsert onto its own ' || t || ' id succeeds'
)
from fx;
select results_eq(
  format('select created_at from public.%I where id = %L', t, id1),
  $$ values ('2001-02-03'::timestamptz) $$,
  'U1''s upsert updated its ' || t || ' row'
)
from fx;
select isnt_empty(
  format('update public.%I set deleted_at = now() where id = %L returning id', t, id1),
  'U1 soft-deletes its ' || t || ' row'
)
from fx;

-- Lookup tables: authenticated reads all of them and writes none
select set_eq(
  format('select value from public.%I', t),
  format('select value from lk where t = %L', t),
  'authenticated reads every row of ' || t
)
from (select distinct t from lk) as l;
select ok(
  (select count(distinct t) = 4 from lk),
  'the four lookup tables have rows to compare'
);
select throws_ok(
  stmt, '42501', null, 'authenticated cannot ' || verb || ' ' || t
)
from unnest(array[
  'reference_sources', 'reference_statuses', 'photo_original_targets', 'photo_upload_states'
]) as t,
  lateral (values
    ('insert into', format('insert into public.%I (value) values (%L)', t, 'nope')),
    ('update', format('update public.%I set description = %L', t, 'x')),
    ('delete from', format('delete from public.%I', t))
  ) as v (verb, stmt);

-- Values outside a lookup table are rejected by its foreign key
select throws_ok(
  $$ insert into public.plant_refs (id, plant_id, source, external_id, url, created_at, updated_at)
     values ('00000000-0000-0000-0000-0000000e6102', '00000000-0000-0000-0000-0000000e1101',
             'nope', 'x', 'https://example.org', now(), now()) $$,
  '23503', null,
  'a plant_refs.source outside reference_sources is rejected'
);
select throws_ok(
  $$ insert into public.reference (id, plant_id, source, fetched_at, payload, status, created_at, updated_at)
     values ('00000000-0000-0000-0000-0000000e7102', '00000000-0000-0000-0000-0000000e1101',
             'wikidata', now(), '{}', 'nope', now(), now()) $$,
  '23503', null,
  'a reference.status outside reference_statuses is rejected'
);
select throws_ok(
  $$ insert into public.photos (id, observation_id, taken_at, width, height, sha256, preview_path,
                                original_target, upload_state, created_at, updated_at)
     values ('00000000-0000-0000-0000-0000000e3102', '00000000-0000-0000-0000-0000000e2101',
             now(), 4, 3, 'ab', 'p.jpg', 'app_only', 'nope', now(), now()) $$,
  '23503', null,
  'a photos.upload_state outside photo_upload_states is rejected'
);

-- U1 hard-deletes its rows, children first
select results_eq(
  format('delete from public.%I where id = %L returning id', t, id1),
  format('values (%L::uuid)', id1),
  'U1 hard-deletes its ' || t || ' row'
)
from fx order by ord desc;

reset role;
select is_empty(
  $$ select 1 from public.observations where id = '00000000-0000-0000-0000-0000000e2203' $$,
  'U1''s plant delete cascades to U2''s observation of it'
);

select * from finish();
rollback;
