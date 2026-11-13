pgTAP tests run by `supabase test db` (`npm run db:test`) against the local
stack, as `postgres`. The CLI installs the `pgtap` extension for the run and
drops it afterwards: the files must not create it.

One file per concern, each one transaction (`begin; select plan(n); ...
select * from finish(); rollback;`) with an exact plan:

- `structure.test.sql`: the security shape in the catalog (the exact list of
  tables, views and functions, RLS on, policies, grants to `anon` and
  `authenticated`, triggers).
- `rls_owner.test.sql`: owner-only reads and writes on every synced table,
  including the push upsert (`insert ... on conflict (id) do update`), and
  read-only lookup tables.
- `anon.test.sql`: `anon` reads and writes nothing.
- `triggers.test.sql`: server `updated_at`, `loc` from `lat`/`lon`, the
  observation checks and the natural keys.
- `plants_near.test.sql`: the RPC's radius, filters and owner scoping.

Each file creates its own users and rows (rolled back): the tests do not
depend on `seed.sql` and pass after `supabase db reset --no-seed`. Switch user
with `set local role authenticated;` plus
`select set_config('request.jwt.claims', '{"sub":"<uuid>","role":"authenticated"}', true);`,
back to the owner with `reset role;`. A new table, view or function
makes `structure.test.sql` fail until it is listed there and, since Supabase
grants `anon` every new object in `public` by default, until a revoke takes
`anon`'s privileges back.
