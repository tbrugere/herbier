# OCaml conventions review

Applies `docs/style-guide.md` to the changed OCaml. Read the style guide first; it is the
reference, this file lists what to look for in a diff.

## Scope

Any changed `*.ml`, `*.mli`, `dune`, `dune-project`. Never flag generated files
(`app/domain/version.ml`, `*.opam`). `lib/postgrest/` sources are human-written: review them
the same way, the author decides.

## Checklist

- **Imperative constructs where a combinator or recursion does.** `for`/`while`, `ref` or
  `mutable` outside a small local scope or an FFI-forced cell, `Array` where a list or `Seq`
  reads better. Suggest the `List`/`Seq` function or the recursive form.
- **`if` where `match` reads better**, and a function that binds an argument only to match on
  it immediately instead of destructuring in the definition or using `function`. The
  `match () with | () when c1 -> ... | () -> ...` form is the idiom for a condition chain.
- **Unneeded abstraction**: a functor, first-class module or record of functions with one
  instantiation; a polymorphic helper used at one type. The reverse too: three copies of the
  same ten lines that a plain function would replace.
- **Typing that lets illegal states in**: `string` where a variant or a typed id exists, a
  boolean pair where a three-constructor variant is meant, `option` of a list where the empty
  list means the same thing, a `_` wildcard on a variant the project owns (a future constructor
  falls through silently). GADTs and polymorphic variants are allowed where they buy a real
  guarantee and not elsewhere.
- **Binding operators**: `let*`/`let+`/`and+` from the right `Syntax` module (Result, Option,
  Fut, the project's react `Syntax`), opened locally inside the function, never at top level;
  `let*` on signals only at screen level; the `let*` body returning a plain value where `let+`
  was meant.
- **`Seq` where pertinent**: paging through pull results, cursors, file lists; not for a small
  materialised list, and no `to_seq`/`of_seq` ping-pong.
- **Modules and interfaces**: one concern per file, an `.mli` for every library module (screens
  included), doc comments in the `.mli` not the `.ml`, `t` for a module's main type,
  snake_case files. No top-level `open` of project modules; `open Util`-style opens at the top
  of a file are a finding. Local `let open M in` is fine.
- **Errors**: a project-local `result` error variant for recoverable failures, exceptions only
  for invariants; no `Option.get`, `List.hd`, `Result.get_ok` on data that comes from outside
  (JSON, SQL rows, the DOM, an intent).
- **Reactive code** (`app/ui`): signals for state and events for occurrences, pure functions
  in `S.map`/`E.map`, no setter call inside an update step, every binding released per screen
  with `S.stop ~strong:true`; `S.keep` does not exist.
- **FFI** (`app/bindings`): `Jv.t` never leaves the bindings library; conversions to plain OCaml
  at the boundary; a binding exposes the JS API's shape, not domain vocabulary.
- **Formatting**: files the author touched are `dune fmt` clean (`.ocamlformat`: version 0.29.0,
  default profile, margin 80, `break-infix = fit-or-vertical`). Point out a file that is not,
  do not list every line.
- **Dune**: a `libraries` field that violates the direction in `layout.md` §2 is architecture's
  finding; a `public_name` missing on an `app/` library or a wrong library name is yours.

## Output

Write `.review-report/ocaml-conventions.md`:

```
# OCaml conventions review

## Findings
| Severity | Location | Issue | Suggestion |
| --- | --- | --- | --- |
| blocker/high/medium/low/nit | path:line | what's wrong | concrete fix |

## Questions for the author
- ...
```

Review only; no edits. Cite `file:line`. One row per finding. Raise uncertain findings as
`low` with the assumption named. An empty table is fine.
