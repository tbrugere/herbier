# Tests review

Missing coverage, fixture correctness, and tests that prove nothing.

## Scope

Any changed non-generated `*.ml` under `lib/` or `app/`, and anything under `test/`.

## What the project tests, and how (`style-guide.md` §12, `layout.md` §6)

Native alcotest, in `test/<library>/`, for every library without a Brr dependency: `domain`,
`lib/postgrest`, `refs`. Recorded payloads under `test/fixtures/` (external APIs) and
`test/postgrest/fixtures/` (PostgREST exchanges, recorded by a script, never hand-edited).
Device-only layers (`bindings`, `store`, `sync`, `photos`, `geo`, `ui`) have no unit tests;
their plan step names a manual check instead. `test/postgrest/` is the reference for the style:
a mock backend, `Alcotest.testable` through a JSON rendering, one `check` per fact.

## Checklist

- **A pure function without a test.** New code in `domain/`, `lib/postgrest/` or `refs/` with
  no test exercising it; a bug fix with no test that failed before the fix.
- **The "Done:" criterion of the step** (`docs/plan.md`) not reflected in a test when it is
  checkable natively, e.g. "digitale finds Digitale pourpre" wants a search test, "is_null on a
  non-nullable column is rejected by the compiler" wants a compile-failure test or a note that
  it is checked by the type.
- **Each branch, each constructor.** A decoder with one happy-path test and none for `null`,
  missing key, wrong type; a filter DSL with the simple case tested and not the list or tree
  case; an enum with the known labels tested and not an unknown one.
- **Boundary values.** Exactly 500 m, an empty list, a single element, the last page, a
  timestamp with microseconds and an offset, a name with a comma or a quote.
- **Tests that test the mock.** A test whose expected value is produced by the same function
  under test, or that only checks the mock recorded a call without checking the request's
  content; a replay that compares against a URL the author wrote by hand instead of the
  recorded exchange.
- **Weak assertions.** `Alcotest.(check bool) "ok" true (Result.is_ok r)` where the value should
  be compared; `pass` with no check; catching all exceptions and calling it a success.
- **Fixtures.** A recorded fixture edited by hand (diff shows a change without the recorder
  script running); a seed value in the test that disagrees with `seed.sql`; a scenario whose
  name says one thing and whose data does another; fixtures that depend on today's date.
- **Determinism.** Order-dependent assertions on sets (embedded rows, search results) without
  sorting; tests that need the network or Docker without saying so and skipping cleanly.
- **Test placement and dune.** A test for `domain` under `test/postgrest`; a `test` stanza
  missing `(deps (glob_files ...))` for fixtures it reads; a test executable named like a
  library module.
- **Skipped or disabled tests** without a note of why and when they come back.
- **Compile-time guarantees documented.** Where the test for a property is "it does not
  typecheck", the plan or a comment in the test names it; otherwise the guarantee erodes
  unnoticed.

## Output

Write `.review-report/tests.md`:

```
# Tests review

## Findings
| Severity | Location | Issue | Suggestion |
| --- | --- | --- | --- |
| blocker/high/medium/low/nit | path:line | what's wrong | concrete fix |

## Questions for the author
- ...
```

Review only; no edits. Cite `file:line`. An empty table is fine.
