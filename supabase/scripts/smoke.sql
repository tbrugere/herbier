-- Smoke check of the migration on a freshly seeded local database (CI runs
-- it after `supabase start`). Everything runs in one rolled-back transaction;
-- a failed assert stops psql with an error.

begin;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-00000000d001","role":"authenticated"}',
  true
);

insert into public.observations (id, plant_id, at, lat, lon, created_at, updated_at)
values (
  '00000000-0000-0000-0000-0000000b0001', '00000000-0000-0000-0000-00000000a001',
  now(), 48, 7, now(), '2000-01-01'
);

do $$
begin
  assert (select updated_at > '2001-01-01' from public.observations),
    'an insert keeps the device updated_at';
  assert (select loc is not null from public.observations),
    'the loc trigger did not set loc';
  assert (
    select count(*) = 1
    from public.plants_near('SRID=4326;POINT(7 48)'::extensions.geography, 500)
  ), 'plants_near misses the observed plant';
  assert (
    select count(*) = 0
    from public.plants_near('SRID=4326;POINT(8 48)'::extensions.geography, 500)
  ), 'plants_near returns a plant 70 km away';
end;
$$;

do $$
begin
  assert (select count(*) = 10 from public.reference_sources),
    'authenticated cannot read the reference_sources lookup';
  begin
    insert into public.plant_refs (id, plant_id, source, external_id, url, created_at, updated_at)
    values ('00000000-0000-0000-0000-0000000c0001', '00000000-0000-0000-0000-00000000a001',
            'nope', 'x', 'https://example.org', now(), now());
    raise exception 'a source outside the lookup table was accepted';
  exception
    when foreign_key_violation then null;
  end;
  begin
    insert into public.reference_sources (value) values ('nope');
    raise exception 'authenticated can write a lookup table';
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-00000000d002","role":"authenticated"}',
  true
);

do $$
begin
  assert (select count(*) = 0 from public.plants), 'another user sees the plants';
end;
$$;

set local role anon;

do $$
begin
  perform count(*) from public.plants;
  raise exception 'anon can read plants';
exception
  when insufficient_privilege then null;
end;
$$;

rollback;
