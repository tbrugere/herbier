# Error handling review

Swallowed errors, exceptions crossing boundaries, and the lifecycle of bindings, futures and
resources.

## Scope

Any changed `*.ml`, `*.js`, `*.kt`, `*.py`, `*.sh`. Skip if none changed.

## Checklist

- **Exception where a `result` is the contract.** A library function that can raise on
  external input (`Yojson.Safe.from_string`, `int_of_string`, `Ptime.of_rfc3339` misuse,
  `List.assoc`, `Option.get`) called without being caught and mapped; `with _ ->` catching
  everything including `Stack_overflow` and `Out_of_memory`; the wrong exception named in a
  `try ... with` (the real one escapes).
- **Error dropped on the floor.** `let _ = fut in`, `ignore (f ())` on a function returning a
  result, `Result.iter` where the error branch matters, an `Error _ -> []` that turns a failure
  into an empty list the UI then shows as "no plants".
- **Error context lost.** Mapping every failure to one constructor so the caller cannot tell
  a 401 (refresh the token and retry) from a 409 (conflict, keep the outbox entry) from a
  network failure (back off); dropping PostgREST's JSON error body, whose `code` is the
  Postgres error code.
- **Retries and backoff.** A retry loop without a bound; a retry on a non-idempotent request
  without the upsert `Prefer`; backoff state kept in a ref that survives a screen change.
- **Reactive lifecycle.** Bindings created by a screen not released when the router switches
  (`S.stop ~strong:true` on every binding the screen created, never on a shared signal);
  `E.on`/`Ev.listen` registrations without the matching removal; a `Fut` resolving after the
  screen is gone and touching a removed element.
- **Resources.** A SQLite transaction without a rollback path on error; a file written to
  `Directory.Data` without the temp-then-rename pattern where a partial write would be read as
  a valid preview; a camera stream not stopped on leave; a MapLibre map not removed.
- **Boundaries with JS.** A `Jv.Error.t` rejection converted with `Jv.Error.message` only,
  losing the `name`/`code` that distinguishes permission denied from not found; a Kotlin
  plugin that resolves the JS promise with `null` on failure instead of rejecting.
- **Scripts.** `set -euo pipefail` missing; a `docker` or `psql` failure that leaves containers
  running without the trap; a Python script that catches `Exception` and prints.
- **Logging.** Errors swallowed silently with no trace at all in paths that will run on a
  phone with no debugger attached; conversely, a user's data (notes, coordinates) printed to
  the console.

## Output

Write `.review-report/error-handling.md`:

```
# Error handling review

## Findings
| Severity | Location | Issue | Suggestion |
| --- | --- | --- | --- |
| blocker/high/medium/low/nit | path:line | what's wrong | concrete fix |

## Questions for the author
- ...
```

Review only; no edits. Cite `file:line`. Raise uncertain findings as `low` with the assumption
named. An empty table is fine.
