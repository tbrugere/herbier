-- anon (a request with the publishable key and no session) reads, writes
-- and calls nothing: every statement fails on a missing grant, so RLS is not
-- even reached. A plant and an observation exist so there is something to
-- read.

begin;
select plan(35);

insert into auth.users (
  instance_id, id, aud, role, email, email_confirmed_at,
  confirmation_token, recovery_token, email_change, email_change_token_new,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000e0001',
  'authenticated', 'authenticated', 'u1@herbier.test', now(), '', '', '', '',
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
);
insert into public.plants (id, owner_id, display_name, aliases, notes, created_at, updated_at)
values (
  '00000000-0000-0000-0000-0000000e1101', '00000000-0000-0000-0000-0000000e0001',
  'Plante', '{}', '', now(), now()
);
insert into public.observations (id, owner_id, plant_id, at, lat, lon, created_at, updated_at)
values (
  '00000000-0000-0000-0000-0000000e2101', '00000000-0000-0000-0000-0000000e0001',
  '00000000-0000-0000-0000-0000000e1101', now(), 48, 7, now(), now()
);

set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);

select throws_ok(
  format('select * from public.%I', t), '42501', null, 'anon cannot read ' || t
)
from unnest(array[
  'plants', 'observations', 'photos', 'tags', 'plant_tags', 'plant_refs', 'reference',
  'reference_sources', 'reference_statuses', 'photo_original_targets', 'photo_upload_states'
]) as t;

select throws_ok(
  format('insert into public.%I default values', t), '42501', null, 'anon cannot insert into ' || t
)
from unnest(array[
  'plants', 'observations', 'photos', 'tags', 'plant_tags', 'plant_refs', 'reference'
]) as t;

select throws_ok(stmt, '42501', null, 'anon cannot ' || verb || ' ' || t)
from unnest(array[
  'plants', 'observations', 'photos', 'tags', 'plant_tags', 'plant_refs', 'reference'
]) as t,
  lateral (values
    ('update', format('update public.%I set updated_at = now()', t)),
    ('delete from', format('delete from public.%I', t))
  ) as v (verb, stmt);
select throws_ok(
  $$ select * from public.plants_near('SRID=4326;POINT(7 48)', 500) $$,
  '42501', null,
  'anon cannot call plants_near'
);
select throws_ok(
  format('select public.%I()', f), '42501', null, 'anon cannot call the trigger function ' || f
)
from unnest(array['set_updated_at', 'observations_set_loc']) as f;

select * from finish();
rollback;
