# Architecture review

The change against `docs/layout.md` and `docs/architecture.md`: dependency direction, purity
of the pure libraries, the sans-IO rule, duplication, and drift between the code and the docs.

## Scope

Any changed `*.ml`, `*.mli`, `dune`, `dune-project`.

## The rules to check against

From `layout.md` §2, enforced by each `dune` file's `libraries`:

```
domain    <- ptime, uuidm                 (no JSON library, no Brr)
postgrest <- yojson, ptime, uri           (lib/; no domain, no Brr, no HTTP)
refs      <- domain, yojson               (no Brr)
bindings  <- brr                          (no domain, no logic)
store     <- domain, bindings, postgrest
sync      <- domain, store, bindings, postgrest
photos | refs_io | geo <- domain, store, bindings  (refs_io also refs; siblings never import each other)
ui        <- everything above + react, reactiveData
main      <- ui
```

## Checklist

- **Dependency direction.** A `libraries` field or an `open`/qualified reference that goes
  against the table: `Yojson` or `Jv` in `domain/`, `Brr` in `refs/` or `lib/postgrest/`,
  `herbier_photos` used from `herbier_geo`, store code reaching into `ui`.
- **Logic in the wrong layer.** Domain rules (merge, place clustering, link classification)
  written in a screen or in `store/`; SQL in `ui/`; HTTP or Brr fetch inside `lib/postgrest/`
  (it is sans-IO: requests are values, the transport lives in `sync/transport.ml`); a binding
  module that validates or transforms beyond the JS shape.
- **Orchestration.** Cross-service sequences (save, then outbox push, then reference fetch,
  then geocode) belong in `ui/app.ml`; a sibling service calling another is the smell.
- **Duplication and drift.** Two definitions of the same record or variant in two libraries
  (the domain type and a store copy); a second decoder for a shape `Postgrest.Row` already
  decodes; a constant (500 m, preview size, backoff) defined twice; a column name as a string
  literal outside `store/tables.ml`.
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
