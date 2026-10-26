# CI / infra review

Build files, the lock, workflows, package pins, scripts.

## Scope

`.github/**`, `dune`, `dune-project`, `dune.lock/**`, `*.opam`, `package.json`,
`package-lock.json`, `scripts/**`, `supabase/config.toml`, `.ocamlformat`, `treehouse.toml`.

## Checklist

- **`dune.lock/` changes.** A re-lock picks up every newer release in the opam repository,
  including the compiler (it moved 5.5.1 to 5.5.2 once by accident). A lock diff must be
  explained by a dependency change in `dune-project`; an unexplained compiler or ppxlib bump
  is a finding. New `.pkg` files without a matching `dune-project` edit, or the reverse.
- **`dune-project` and opam files.** A dependency added to a library's `dune` but not to its
  package's `depends`; a `:with-test` dependency used by non-test code; `herbier.opam` and
  `postgrest.opam` are generated (`generate_opam_files`), never hand-edited; the `postgrest`
  package must stay free of Brr and of Herbier.
- **Dune stanzas.** `(modes js)` on the app executable; `public_name` on every `app/` library;
  the root `dune` `(dirs ...)` exclusion list still covering `node_modules`, `android`,
  `supabase`, `docs`, `scripts`, `www`, `.lavish`; the `env` stanza's warning flags not
  silently loosened (`-w +27+32..39` in dev).
- **Workflows.** Every job has the least `permissions:`; `ocaml/setup-ocaml` only provides
  dune, the locked compiler is built by `dune build` and cached on `dune.lock/**`; `dune fmt
  --check`, `dune test` and the tables check present in `ci.yml`; the Supabase job runs the
  pgTAP tests and the dump check; `android.yml` still uploads the debug APK artifact; actions
  pinned to a major at least.
- **npm.** `package.json` pins compatible majors (Capacitor 8 plugins together); a plugin
  added without `package-lock.json` updated; `sass` and `esbuild` are dev dependencies; no
  script that assumes a global install (`npx --no-install` in build scripts).
- **Scripts.** `set -euo pipefail`; `git rev-parse --show-toplevel` for paths rather than
  `$PWD`; Docker helpers that clean up on exit; Python scripts runnable with `uv run` and
  stdlib only unless the header declares dependencies.
- **Generated files staleness.** `supabase/schema/**` after a migration; `app/store/tables.ml`
  after a schema change; `test/postgrest/fixtures/scenarios.json` after a change to
  `scenarios.spec.json`, `schema.sql` or `seed.sql` (re-record, do not edit).
- **Developer loop.** A change that breaks `scripts/dev.sh`, the `www` symlink, or the
  `dune build @check --watch` + ocamllsp setup documented in the docs.
- **Secrets in CI** are security's finding; mention and defer.

## Output

Write `.review-report/ci-infra.md`:

```
# CI / infra review

## Findings
| Severity | Location | Issue | Suggestion |
| --- | --- | --- | --- |
| blocker/high/medium/low/nit | path:line | what's wrong | concrete fix |

## Questions for the author
- ...
```

Review only; no edits. Cite `file:line`. An empty table is fine.
