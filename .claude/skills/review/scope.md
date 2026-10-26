# Scope review

The change against the plan step it implements. Not a code reviewer: a reviewer of *what* was
done versus what was asked, including work that is still uncommitted or sits on an unmerged
base branch.

## Scope

Runs whenever a plan step is known: from the branch name (`<type>/m0-2-...`), the PR body, or
the orchestrator's context file. Reads `docs/plan.md` for the step text, its "Depends:" and
"Done:" lines, and the neighbouring steps. Reads `.implement/plan.md` if present (the
implementation plan with its design decisions). Reads the whole diff, committed and
uncommitted, and `git log --oneline <base>..HEAD`.

## What to establish

1. **Missing.** Every element the step names (files, modules, functions, migrations, scripts,
   doc updates) that is absent or stubbed; every assertion of the "Done:" criterion that
   nothing in the diff demonstrates. A stub is acceptable only when the implementation plan
   says so and names the step that fills it.
2. **Extra.** Work that belongs to another step (name it), to no step, or that the plan lists
   as deferred or v2. Refactors of untouched code. New dependencies the step does not need.
   Changes under `lib/postgrest/` source files, which the AI policy reserves to the human.
3. **Misplaced.** Files that `layout.md` puts elsewhere; logic in a layer the step did not
   target.
4. **Drift from the implementation plan.** A signature, type or behaviour that differs from
   `.implement/plan.md` without an entry in its `## Design decisions`; a design decision listed
   there that contradicts `stack.md`, `architecture.md` or `layout.md` and was not flagged as
   needing the user.
5. **Unmerged ground.** If the branch is based on another unmerged branch, say which commits
   are that branch's and review only the rest; if the step's "Depends:" names a step whose work
   is not on `main`, say whether the branch carries it or assumes it.
6. **Docs.** Whether `docs/plan.md`, `layout.md` or `architecture.md` need an edit because the
   step changed something they state, and whether the diff makes it.

## Output

Write `.review-report/scope.md`:

```
# Scope review

Step: <id and one-line summary from docs/plan.md>
Base: <branch, merged or not>

## Done criterion
| Assertion | Evidence in the diff | Status |
| --- | --- | --- |
| ... | path:line or test name | met / not met / not checkable here |

## Findings
| Severity | Kind | Location | Issue | Suggestion |
| --- | --- | --- | --- | --- |
| blocker/high/medium/low/nit | missing/extra/misplaced/drift/docs | path or step | what | do what |

## Questions for the author
- ...
```

Severity: a "Done:" assertion not met is `high`; work from another step mixed in is `medium`
unless it is large or risky; a missing doc edit is `low`. Review only; no edits. An empty
findings table with a fully met criterion table is the good outcome.
