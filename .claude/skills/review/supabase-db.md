# Supabase / DB review

Migrations, row-level security, grants, triggers, and staleness of the schema dump and of
`app/store/tables.ml`. Single-user app: every synced row has an `owner_id` and the policies are
`(select auth.uid()) = owner_id`; that is the model to check against (`architecture.md` §4).

## Scope

`supabase/**`, `app/store/tables.ml`, `app/store/schema.ml`, `app/sync/**`. Never flag the
contents of `supabase/schema/**` (the dump); flag it when stale.

## Checklist

- **Migrations are hand-written, forward-only, timestamped `<timestamp>_<verb>_<object>.sql`.**
  A timestamp older than the latest on `main`, a hand-edited migration already on `main`, a
  migration that depends on data present only locally.
- **Every new `public` table**: `ENABLE ROW LEVEL SECURITY`, a policy per command (`SELECT`,
  `INSERT WITH CHECK`, `UPDATE USING ... WITH CHECK`, `DELETE`) all on `owner_id`, `TO
  authenticated` (never a policy without `TO`, never one that `anon` can satisfy), `owner_id
  uuid not null default auth.uid()` so a client cannot write another user's id, a uuid
  primary key generated on the device, `created_at`/`updated_at timestamptz`, `deleted_at`
  for soft delete, the `moddatetime` trigger on `updated_at`.
- **Grants.** `GRANT SELECT, INSERT, UPDATE, DELETE` to `authenticated` only; no `GRANT ALL`;
  nothing to `anon`; a new function gets `REVOKE EXECUTE FROM public, anon` when it is
  `SECURITY DEFINER`.
- **Extensions** created `WITH SCHEMA extensions`, not in `public`.
- **Soft delete versus uniqueness.** A `UNIQUE` constraint that would block re-creating a row
  after its soft delete; a query or policy that forgets `deleted_at is null`.
- **Sync protocol consistency** (`architecture.md` §4). Push uses `Prefer:
  resolution=merge-duplicates` on the uuid key; pull filters on `updated_at` strictly greater
  than the cursor and orders by it; LWW compares `updated_at` set by the server trigger, not a
  device clock; a delete is a `PATCH` setting `deleted_at`.
- **Staleness.** A migration in the diff with no corresponding change under
  `supabase/schema/` (run `uv run supabase/scripts/schema-dump.py`); a column added, renamed
  or retyped without the matching edit in `app/store/tables.ml` (`scripts/check_tables.py`
  guards it in CI once it exists; until then, check by hand); an enum type changed in SQL
  without its OCaml `enum` record changing.
- **Types across the boundary.** A Postgres type with no `Postgrest.Col.base` constructor
  (`geography`, `tsvector`, arrays) introduced without a plan for how the client reads it;
  `numeric` versus `double precision` chosen without regard to how JSON carries it.
- **Local stack.** `supabase/config.toml` changes (auth providers, sign-ups off) consistent
  with `stack.md`; `seed.sql` rows that violate the policies they will be tested under.
- **pgTAP.** A policy change without a test under `supabase/tests/` once that directory has
  tests.

## Output

Write `.review-report/supabase-db.md`:

```
# Supabase / DB review

## Findings
| Severity | Location | Issue | Suggestion |
| --- | --- | --- | --- |
| blocker/high/medium/low/nit | path:line | what's wrong | concrete fix |

## Questions for the author
- ...
```

Review only; no edits. Cite `file:line`. An empty table is fine.
