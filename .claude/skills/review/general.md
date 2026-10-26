# General review

A fresh-eyes reviewer with no fixed checklist. Reads the whole change and flags anything that
seems wrong, risky, surprising or unclear: the catch-all for what the specialised lenses miss.

## Scope

Every review, all changed files, any language and config and docs. Never flag generated or
recorded files.

## Approach

Read the diff and the surrounding code the way a careful senior engineer would on a first pass.
Prompts to think with, not a script:

- Does the change do what the plan step, the commit messages and the PR text say it does?
- Is anything harder to follow than it needs to be: misleading names, a comment that
  contradicts the code, dead code, a copy-paste not fully adapted?
- Which inputs or failure modes does it not handle? What happens offline, on an empty
  database, on the first run, after an upgrade?
- Does anything look accidental: a debug line, a `TODO`, a fixture edited by hand, a file in
  the wrong directory, a dependency added for one function?
- Is there a simpler way? Would the style guide's "do not go too generic" rule apply?
- Does anything smell off and deserve a second look?

Avoid re-reporting what the specialised lenses cover (conventions, architecture, correctness
classes, error handling, DB, security, tests, web, CI, scope, comments). Your value is what
fits no bucket.

## Conventions

`CLAUDE.md`, `docs/style-guide.md`, `docs/layout.md` and `docs/architecture.md` are the
references when something looks off against the project's norms.

## Output

Write `.review-report/general.md`:

```
# General review

## Findings
| Severity | Location | Issue | Suggestion |
| --- | --- | --- | --- |
| blocker/high/medium/low/nit | path:line | what's wrong | concrete fix |

## Questions for the author
- ...
```

Review only; no edits. Flag only real issues, cite `file:line`, one row per finding. Raise
uncertain findings as `low` with the assumption named; a verify pass adjudicates them. An
empty table is fine.
