---
name: review
description: Evidence-based parallel code review of the current branch or a GitHub PR. Detects what changed, launches only the lens agents whose area was touched, verifies contested findings, calibrates severity, and presents one summary plus the questions for the author. Triggers - "review my branch", "review this PR", "/review", "review before I open a PR".
---

Parallel, gated code review. The orchestrator (this file) computes the changeset, launches ONLY
the lens agents whose area was touched, collects their reports from `.review-report/`, verifies
what needs verifying, calibrates severity and presents one summary. Each lens is a helper file in
this directory.

Lenses:

- [ocaml-conventions.md](ocaml-conventions.md) — the style guide applied: idioms, modules, `.mli`, formatting.
- [correctness.md](correctness.md) — logic bugs: exhaustiveness, option/result handling, GADT and type-level slips, encoding, boundaries.
- [error-handling.md](error-handling.md) — swallowed errors, exceptions crossing boundaries, lifecycle of bindings and resources.
- [architecture.md](architecture.md) — `layout.md` dependency direction, domain purity, sans-IO, duplication, drift from the docs.
- [supabase-db.md](supabase-db.md) — migrations, RLS, grants, triggers, schema dump and `tables.ml` staleness.
- [security.md](security.md) — secrets and keys, untrusted input from intents and APIs, SQL built from strings.
- [tests.md](tests.md) — missing coverage, fixture correctness, tests that test the mock.
- [web.md](web.md) — Sass, tokens, markup, Capacitor and Android configuration.
- [ci-infra.md](ci-infra.md) — dune files and lock, workflows, package pins, scripts.
- [scope.md](scope.md) — the change against its plan step: missing, extra, misplaced work. Always runs when a step is named.
- [comment-hygiene.md](comment-hygiene.md) — comments that do not describe the code; docs that should not be there.
- [general.md](general.md) — fresh-eyes catch-all, no checklist; always runs.
- [verify.md](verify.md) — fact-checks one contested or unsupported finding; triggered in step 6, not file-gated.

# Workflow

**The structure is the point of this skill. Three layers of agents, never collapsed:**

1. **One lens agent per selected lens**, all in parallel (step 5).
2. **One grouping agent** that reads every lens report and turns them into one list of distinct
   findings, each a single checkable claim (step 6a).
3. **One verify agent per finding**, all in parallel, each independent of the lens that raised
   it (step 6b). Every finding is verified, not only the contested ones.

The orchestrator dispatches and calibrates; it never reviews code itself and never verifies a
finding itself, and no lens verifies its own findings. A review where one agent applies the
lenses in turn, or where the reviewer writes its own "verified" section, is not this review:
its findings are unfiltered and fixes made from them may fix problems that do not exist.

If the orchestrator cannot spawn agents (for example it is itself an agent started by a
Workflow script, which has no Agent tool), it must not fall back to doing the lenses itself:
stop and report that the caller has to dispatch the three layers. A Workflow script runs this
skill by calling `agent()` for each lens, then the grouping agent, then one verifier per
finding (see `.claude/skills/implement-workflow/SKILL.md`, "Review inside a Workflow").

## 1. Setup

- Create `.review-report/` if missing; delete any existing files inside it (fresh run).
- Ensure `.review-report/` is in `.gitignore`.

## 2. Resolve mode and compute the changeset

**Mode A — current branch (default).**

- Base defaults to `main`; if the branch is stacked on another feature branch, use that
  (`git merge-base` against candidate branches tells you). `BASE=$(git merge-base HEAD <base>)`.
- Committed changes: `git diff --name-only "$BASE"...HEAD`. Uncommitted changes are reviewed
  too: `git diff --name-only HEAD`. Lenses read full files from the working tree.

**Mode B — a GitHub PR (number or URL given).**

- `gh pr view <n> --json number,title,body,baseRefName,headRefName,headRefOid,files`
- `git fetch origin pull/<n>/head`; `HEAD_OID` from the view; `git fetch origin <base>`;
  `BASE=$(git merge-base "$HEAD_OID" origin/<base>)`.
- Diff: `gh pr diff <n>`. Lenses read files with `git show "$HEAD_OID":<path>`.
- Ask before `gh pr checkout`; if refused, do not touch the working tree.

## 3. Shared context file

Write `.review-report/_context.md`: mode, base, PR number/title/body (Mode B), how to read a
file, the plan step being implemented if known (from the branch name `<type>/m0-2-...` or the
PR body) and its text from `docs/plan.md`, and the changed files grouped by area:
`lib/`, `app/domain`, `app/bindings`, `app/store`, `app/sync`, `app/photos`, `app/refs`,
`app/refs_io`, `app/geo`, `app/ui`, `web/`, `android/`, `supabase/`, `test/`, `scripts/`,
`.github/`, build files (`dune*`, `*.opam`, `package.json`, `capacitor.config.ts`), `docs/`.

Every lens reads this file first.

## 4. Gate

Launch a lens only if a changed path matches. Print the launch/skip decision for each.

| Lens | Launch when a changed path matches |
| --- | --- |
| ocaml-conventions | any `*.ml`, `*.mli`, `dune`, `dune-project` |
| correctness | any `*.ml`, `*.mli`, `*.sql`, `*.sass`, `*.js`, `*.kt`, `*.py`, `*.sh` |
| error-handling | any `*.ml`, `*.js`, `*.kt`, `*.py`, `*.sh` |
| architecture | any `*.ml`, `*.mli`, `dune`, `dune-project` |
| supabase-db | `supabase/**`, `app/store/tables.ml`, `app/store/schema.ml`, `app/sync/**` |
| security | any code file, `.github/**`, `android/app/src/main/AndroidManifest.xml`, `capacitor.config.ts`, `supabase/config.toml` |
| tests | any non-generated `*.ml` under `lib/` or `app/`, or anything under `test/` |
| web | `web/**`, `android/**`, `capacitor.config.ts`, `app/ui/**` |
| ci-infra | `.github/**`, `dune*`, `dune.lock/**`, `*.opam`, `package.json`, `package-lock.json`, `scripts/**`, `supabase/config.toml`, `.ocamlformat` |
| scope | always when a plan step is known (branch name or PR body); otherwise skip and say so |
| comment-hygiene | any changed code or config file, and `docs/**` |
| general | always |

Never flag the contents of generated or recorded files: `herbier.opam`, `postgrest.opam`,
`dune.lock/**`, `supabase/schema/**`, `test/postgrest/fixtures/scenarios.json`,
`test/postgrest/fixtures/README.md`, `app/domain/version.ml`, `www`. Flag them only when they are
stale against their source (ci-infra, supabase-db).

## 5. Dispatch in parallel

One message, every selected lens. Each prompt: the helper file to read in full and follow; the
context file; mode, base, `HEAD_OID`; the subset of changed files in its scope; the reminder to
surface low-confidence findings marked `low` with the unverified assumption named; the
instruction to write only `.review-report/<lens>.md`. Lenses review; they never edit source.

## 6. Group, then verify every finding

**6a. Group.** One agent reads every report in `.review-report/` and writes
`.review-report/_findings.md`: the distinct findings, duplicates across lenses merged (keep
every lens that raised it), each with an id, `file:line`, the claim in one sentence, the
trigger, the lens's evidence and suggested fix, and the lens's severity. Lens disagreements
become one finding stating both sides. Questions for the author are listed apart.

**6b. Verify.** One [verify.md](verify.md) agent per finding, all in parallel, none of them a
lens that raised it. Each is told to try to refute the claim and to default to `uncertain`
without primary evidence. Fold the verdicts back: `confirmed` keeps the finding with the
evidence merged in; `refuted` drops it and notes it was checked; `uncertain` becomes a
question for the author. Only confirmed findings are fixed.

## 7. Calibrate severity

Severity = impact if triggered × reachability. Reachability caps severity.

Impact: **critical** (data loss or corruption, another user's rows exposed, a secret key in the
app, auth bypass), **major** (a core flow breaks: record, sync, search; wrong data saved),
**minor** (degraded UX, recoverable error, edge-case wrong result, lost diagnostics),
**cosmetic**.

Reachability: **likely** (normal use), **possible** (uncommon but realistic state), **unlikely**
(an invariant, a type, RLS or a constraint prevents it today), **theoretical** (dead branch).

| | likely | possible | unlikely | theoretical |
| --- | --- | --- | --- | --- |
| **critical** | blocker | blocker | high | low |
| **major** | high | high | medium | low |
| **minor** | medium | low | low | nit |
| **cosmetic** | nit | nit | nit | nit |

State the trigger path and the guard in one clause when downgrading.

## 8. Summarize

Findings grouped by severity, each with `file:line` and the lens; then **Questions for the
author**, aggregated. Resolve the questions with the user before any fix. Reviewing and fixing
are separate steps.

## 9. Post review comments (PR mode, with the user's go-ahead)

Post the approved findings as one pending GitHub review with `gh api` (inline comments on
changed lines, prefix `**[severity] (category)**`, verify evidence folded in). Lines outside
the diff anchor to the nearest changed line with a note. Leave the review pending for the user
to submit, unless told to submit.
