# Correctness review

Logic bugs in changed code: OCaml, SQL, Sass, the small JS and Kotlin layers, scripts.

## Scope

Any changed `*.ml`, `*.mli`, `*.sql`, `*.sass`, `*.js`, `*.kt`, `*.py`, `*.sh`. Skip if no code
changed. Not generated files.

## Checklist, OCaml

- **Wildcard swallowing a case.** `| _ ->` on a variant the project owns, or an or-pattern
  that merges cases with different meanings. Ask: if a constructor is added tomorrow, what
  happens here? Prefer listing the constructors.
- **Option and result confusions.** `None` meaning both "absent" and "null" where the schema
  distinguishes them (an `Unspecified` versus `Value None` case); `Error` branches that return
  `Ok` of a default; a `result` whose error type is `unit` or `string` where a variant exists.
- **GADT and type-level slips.** A type variable that should be locally abstract (`type a.`)
  so a branch narrows the whole function; an existential escaping a match through a `let`; an
  or-pattern across GADT constructors; a phantom index carried as an alias instead of a fresh
  type (so it checks nothing); `_` in a constructor return type where a bounded `[< ...]` was
  meant.
- **Value restriction.** A partial application at top level (`let f = g x`) yielding a weak
  type that the first call fixes; a `.mli` claiming polymorphism the `.ml` cannot provide.
- **Equality.** `==` where `=` is meant, `=` on floats, `compare` on `Ptime.t` versus
  `Ptime.compare`, string comparison where a normalised form was intended (diacritics in
  search).
- **Encoding at the boundaries.** URL query values percent-encoded once, by `Uri`, not by hand
  and not twice; PostgREST list quoting only in list contexts; timestamps rendered with
  `~tz_offset_s:0`; floats with `%.17g` or `Float.to_string`, not `string_of_float` (gives
  `1.`); JSON `null` versus a missing key; `Intlit` and large integers.
- **Off-by-one and boundaries.** `>` versus `>=` at a threshold shared between two files; 500 m
  clustering at exactly 500 m; pagination limits and cursors; `String.sub` bounds.
- **Reactive propagation.** A `S.map` whose function allocates a fresh structure every step so
  `eq` never prunes; a setter called inside a step; an event that should be a signal or the
  reverse; a binding created in a loop and never released.
- **FFI.** A `Jv` property read that can be `undefined` treated as present; a promise rejection
  not mapped; a callback kept beyond its life; numbers that are JS doubles read as `int`.
- **Concurrency with `Fut`.** Two writes racing on the same SQLite row from two awaited
  futures; an outbox entry inserted outside the row's transaction.

## Checklist, SQL

- A migration that is not idempotent where it should be, or that cannot run on the dump's
  state; `NOT NULL` added without a default on a populated table; a unique index that
  conflicts with soft delete (`deleted_at`); `updated_at` not maintained by the trigger; FTS5
  tokenizer options that do not match the search tests.

## Checklist, web and native

- Sass: a selector that depends on markup the OCaml does not produce; a token used that is not
  declared in `_tokens.sass`; `@use` cycles. JS facade: an event listener added per call.
  Kotlin: an intent filter whose host does not match the resolver's classification; `data`
  elements that combine host and path incorrectly.

## Output

Write `.review-report/correctness.md`:

```
# Correctness review

## Findings
| Severity | Location | Issue | Suggestion |
| --- | --- | --- | --- |
| blocker/high/medium/low/nit | path:line | what's wrong | concrete fix |

## Questions for the author
- ...
```

Review only; no edits. Cite `file:line`. Raise uncertain findings as `low` with the assumption
named; a verify pass adjudicates them. An empty table is fine.
