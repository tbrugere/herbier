-- plants_near(pt, radius_m): the caller's live plants with a live
-- observation within radius_m of pt, each once. Distances: 0.001 degree of
-- latitude is about 111 m, 1 degree of longitude at 48N about 74 km.

begin;
select plan(8);

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

-- U1's plants (e11nn) and observations (e21nn), inserted through RLS
set local role authenticated;
select set_config(
  'request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000e0001","role":"authenticated"}', true
);
insert into public.plants (id, display_name, aliases, notes, created_at, updated_at, deleted_at)
values
  ('00000000-0000-0000-0000-0000000e1101', 'Proche', '{}', '', now(), now(), null),
  ('00000000-0000-0000-0000-0000000e1102', 'Lointaine', '{}', '', now(), now(), null),
  ('00000000-0000-0000-0000-0000000e1103', 'Deux fois', '{}', '', now(), now(), null),
  ('00000000-0000-0000-0000-0000000e1104', 'Supprimée', '{}', '', now(), now(), now()),
  ('00000000-0000-0000-0000-0000000e1105', 'Observation supprimée', '{}', '', now(), now(), null),
  ('00000000-0000-0000-0000-0000000e1106', 'Sans position', '{}', '', now(), now(), null),
  ('00000000-0000-0000-0000-0000000e1107', 'À 300 m', '{}', '', now(), now(), null);
insert into public.observations (id, plant_id, at, lat, lon, created_at, updated_at, deleted_at)
values
  -- near: at the centre (48, 7)
  ('00000000-0000-0000-0000-0000000e2101', '00000000-0000-0000-0000-0000000e1101', now(), 48, 7, now(), now(), null),
  -- far: (48, 8), about 74 km east
  ('00000000-0000-0000-0000-0000000e2102', '00000000-0000-0000-0000-0000000e1102', now(), 48, 8, now(), now(), null),
  -- two observations, 111 m and 222 m north of the centre
  ('00000000-0000-0000-0000-0000000e2103', '00000000-0000-0000-0000-0000000e1103', now(), 48.001, 7, now(), now(), null),
  ('00000000-0000-0000-0000-0000000e2104', '00000000-0000-0000-0000-0000000e1103', now(), 48.002, 7, now(), now(), null),
  -- deleted plant, observed at the centre
  ('00000000-0000-0000-0000-0000000e2105', '00000000-0000-0000-0000-0000000e1104', now(), 48, 7, now(), now(), null),
  -- live plant whose only observation at the centre is deleted
  ('00000000-0000-0000-0000-0000000e2106', '00000000-0000-0000-0000-0000000e1105', now(), 48, 7, now(), now(), now()),
  -- no position
  ('00000000-0000-0000-0000-0000000e2107', '00000000-0000-0000-0000-0000000e1106', now(), null, null, now(), now(), null),
  -- about 300 m north of a second centre (45, 5), far from the first
  ('00000000-0000-0000-0000-0000000e2108', '00000000-0000-0000-0000-0000000e1107', now(), 45.0027, 5, now(), now(), null);

-- U2's plant observed at the centre
select set_config(
  'request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000e0002","role":"authenticated"}', true
);
insert into public.plants (id, display_name, aliases, notes, created_at, updated_at)
values ('00000000-0000-0000-0000-0000000e1201', 'Autre', '{}', '', now(), now());
insert into public.observations (id, plant_id, at, lat, lon, created_at, updated_at)
values (
  '00000000-0000-0000-0000-0000000e2201', '00000000-0000-0000-0000-0000000e1201',
  now(), 48, 7, now(), now()
);

select set_config(
  'request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000e0001","role":"authenticated"}', true
);
select set_eq(
  $$ select id from public.plants_near('SRID=4326;POINT(7 48)', 500) $$,
  $$ values ('00000000-0000-0000-0000-0000000e1101'::uuid), ('00000000-0000-0000-0000-0000000e1103') $$,
  'within 500 m: the live plants observed there, not the far, deleted, unobserved, unplaced or other owner''s ones'
);
select results_eq(
  $$ select count(*) from public.plants_near('SRID=4326;POINT(7 48)', 500)
     where id = '00000000-0000-0000-0000-0000000e1103' $$,
  $$ values (1::bigint) $$,
  'a plant with two nearby observations is returned once'
);
select is_empty(
  $$ select id from public.plants_near('SRID=4326;POINT(5 45)', 200) $$,
  'a plant 300 m away is outside a 200 m radius'
);
select set_eq(
  $$ select id from public.plants_near('SRID=4326;POINT(5 45)', 400) $$,
  $$ values ('00000000-0000-0000-0000-0000000e1107'::uuid) $$,
  'a plant 300 m away is inside a 400 m radius'
);
select is_empty(
  $$ select id from public.plants_near('SRID=4326;POINT(8.5 48)', 500) $$,
  'no plant within 500 m of a point 37 km from every observation'
);
select is(
  (select display_name from public.plants_near('SRID=4326;POINT(7 48)', 500)
   where id = '00000000-0000-0000-0000-0000000e1101'),
  'Proche',
  'plants_near returns whole plants rows'
);
select set_eq(
  $$ select id from public.plants_near('SRID=4326;POINT(7 48)'::extensions.geography, 500) $$,
  $$ values ('00000000-0000-0000-0000-0000000e1101'::uuid), ('00000000-0000-0000-0000-0000000e1103') $$,
  'plants_near takes a geography value as well as EWKT text'
);

select set_config(
  'request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000e0002","role":"authenticated"}', true
);
select set_eq(
  $$ select id from public.plants_near('SRID=4326;POINT(7 48)', 500) $$,
  $$ values ('00000000-0000-0000-0000-0000000e1201'::uuid) $$,
  'U2 gets only its own plant at the same point'
);

select * from finish();
rollback;
