-- The schema's security shape, read from the catalog: the exact table list,
-- RLS on everywhere, the policies, the grants to anon and authenticated, the
-- trigger functions' privileges and the triggers. A new table, view or
-- function makes the *_are checks fail until it is listed here and given its
-- tests. Supabase's default privileges give anon every new object in public
-- until a revoke takes them back, so anon's privileges are also checked over
-- the whole schema, not only over the listed objects.

begin;
select plan(55);

select tables_are(
  'public',
  array[
    'plants', 'observations', 'photos', 'tags', 'plant_tags', 'plant_refs', 'reference',
    'reference_sources', 'reference_statuses', 'photo_original_targets', 'photo_upload_states'
  ],
  'public holds exactly the 7 synced tables and the 4 lookup tables'
);
select views_are('public', array[]::name[], 'public holds no view');
select materialized_views_are('public', array[]::name[], 'public holds no materialized view');
select functions_are(
  'public', array['plants_near', 'set_updated_at', 'observations_set_loc'],
  'public holds exactly plants_near and the two trigger functions'
);

select is_empty(
  $$ select relname from pg_class
     where relnamespace = 'public'::regnamespace and relkind in ('r', 'p', 'v', 'm', 'f')
       and has_table_privilege('anon', oid, 'SELECT, INSERT, UPDATE, DELETE') $$,
  'anon can read or write no table or view in public'
);
select is_empty(
  $$ select oid::regprocedure from pg_proc
     where pronamespace = 'public'::regnamespace
       and has_function_privilege('anon', oid, 'EXECUTE') $$,
  'anon can execute no function in public'
);

select is_empty(
  $$ select relname from pg_class
     where relnamespace = 'public'::regnamespace and relkind in ('r', 'p')
       and not relrowsecurity $$,
  'every table in public has row-level security enabled'
);

select policies_are(
  'public', t,
  array[t || '_select_own', t || '_insert_own', t || '_update_own', t || '_delete_own'],
  t || ' has exactly the four owner-only policies'
)
from unnest(array[
  'plants', 'observations', 'photos', 'tags', 'plant_tags', 'plant_refs', 'reference'
]) as t;

select is_empty(
  $$ select tablename, policyname from pg_policies
     where schemaname = 'public' and roles <> '{authenticated}' $$,
  'every policy in public applies to authenticated only'
);

select policies_are('public', t, array[t || '_select'], t || ' has only its select policy')
from unnest(array[
  'reference_sources', 'reference_statuses', 'photo_original_targets', 'photo_upload_states'
]) as t;

select table_privs_are(
  'public', t, 'authenticated', array['SELECT', 'INSERT', 'UPDATE', 'DELETE'],
  'authenticated can select, insert, update and delete on ' || t
)
from unnest(array[
  'plants', 'observations', 'photos', 'tags', 'plant_tags', 'plant_refs', 'reference'
]) as t;

select table_privs_are(
  'public', t, 'authenticated', array['SELECT'],
  'authenticated can only select on ' || t
)
from unnest(array[
  'reference_sources', 'reference_statuses', 'photo_original_targets', 'photo_upload_states'
]) as t;

select table_privs_are(
  'public', t, 'anon', array[]::text[],
  'anon has no privilege on ' || t
)
from unnest(array[
  'plants', 'observations', 'photos', 'tags', 'plant_tags', 'plant_refs', 'reference',
  'reference_sources', 'reference_statuses', 'photo_original_targets', 'photo_upload_states'
]) as t;

select function_privs_are(
  'public', 'plants_near', array['extensions.geography', 'double precision'],
  'anon', array[]::text[],
  'anon cannot execute plants_near'
);
select function_privs_are(
  'public', 'plants_near', array['extensions.geography', 'double precision'],
  'authenticated', array['EXECUTE'],
  'authenticated can execute plants_near'
);

select function_privs_are(
  'public', f, array[]::text[], r, array[]::text[],
  r || ' cannot execute ' || f
)
from unnest(array['set_updated_at', 'observations_set_loc']) as f,
  unnest(array['anon', 'authenticated']) as r;

select triggers_are('public', t, array[t || '_set_updated_at'], t || ' has only its updated_at trigger')
from unnest(array['plants', 'photos', 'tags', 'plant_tags', 'plant_refs', 'reference']) as t;
select triggers_are(
  'public', 'observations', array['observations_set_updated_at', 'observations_set_loc'],
  'observations has its updated_at and loc triggers'
);

select is(
  (select prosecdef from pg_proc
   where oid = 'public.plants_near(extensions.geography, double precision)'::regprocedure),
  false,
  'plants_near is security invoker, so RLS applies to its caller'
);

select * from finish();
rollback;
