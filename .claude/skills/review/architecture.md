# Architecture review

The change against `docs/layout.md` and `docs/architecture.md`: dependency direction, purity
of the pure libraries, the sans-IO rule, duplication, and drift between the code and the docs.

## Scope

Any changed `*.ml`, `*.mli`, `dune`, `dune-project`.

## The rules to check against

`layout.md` §2's "Dependency direction" block, enforced by each `dune` file's `libraries`
(read it there, not from a copy). In short: the pure libraries (`domain`, `net`, `refs`,
`photos`, `geo`, `store`, `sync_core`, `ui_model`, and `lib/postgrest/`) have no Brr; each
`*_io` library and `sync` is the Brr half of its pure one; `photos_io`, `refs_io` and `geo_io`
never import each other; `ui` sits above everything, `main` above `ui`.

## Checklist

- **Dependency direction.** A `libraries` field or an `open`/qualified reference that goes
  against the block: `Jv` in `domain/`, `Brr` in a pure library (`refs/`, `store/`,
  `sync_core/`, `ui_model/`, `lib/postgrest/`), `herbier_photos_io` used from `herbier_geo_io`,
  store code reaching into `ui`.
- **Logic in the wrong layer.** Domain rules (merge, place clustering, link classification)
  written in a screen or in `store/`; SQL in `ui/`; HTTP or Brr fetch inside `lib/postgrest/`
  (it is sans-IO: requests are values, the transport lives in `sync/net/transport.ml`); IO
  (Brr, Fut, bindings) in a pure library instead of its `*_io` half; a binding
  module that validates or transforms beyond the JS shape.
- **Orchestration.** Cross-service sequences (save, then outbox push, then reference fetch,
  then geocode) belong in `ui/app/` (App: Core, Geocoding, Reference_fetch, Packs, in that
  order; a module calls only those before it); one IO library (`photos_io`, `refs_io`,
  `geo_io`) calling another is the smell.
- **Duplication and drift.** Two definitions of the same record or variant, in two libraries
  (the domain type and a store copy) or side by side in one module (a private "wire" record
  mirroring a public one, a field added only to keep a caller unchanged); near-identical
  functions that differ by a constant; a second decoder for the rows of a table `Tables`
  already declares; a constant (500 m, preview size, backoff) defined twice; a column name as a
  string literal outside `store/tables.ml`. Plain data that is not a table (a JSON file, a
  catalog) is decoded with an ordinary decoder such as `ppx_deriving_yojson`, not by
  declaring its fields as `Postgrest.Col` columns.
- **Leftovers of an earlier design.** After a rewrite: fields, helpers, comments or tests that
  only made sense for the previous approach.
- **Design debt introduced.** A new abstraction with one use; a module that will obviously
  need to be split before the next step; a "temporary" global `ref`.
- **Drift from the docs.** A file placed elsewhere than `layout.md` says, a protocol detail
  (LWW rule, soft delete, outbox transaction) implemented differently from `architecture.md`,
  a name that differs from the one the docs use for the same thing. The fix can be in the code
  or in the doc; say which and why.

## Output

Write `.review-report/architecture.md`:

```
# Architecture review

## Findings
| Severity | Location | Issue | Suggestion |
| --- | --- | --- | --- |
| blocker/high/medium/low/nit | path:line | what's wrong | concrete fix |

## Questions for the author
- ...
```

Review only; no edits. Cite `file:line` and the doc section the finding rests on. An empty
table is fine.
