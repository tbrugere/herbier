---
name: implement-workflow
description: Implement one step (or a small group of steps) of docs/plan.md end to end, autonomously - plan, tests written in parallel by a background agent (red), implementation (green), review agents, fixes, draft PR, report. Use when the user says "implement M0.2", "do step 11", "implement the toolchain milestone", or names a plan step.
argument-hint: "[M0.2 | step 11 | M0.2-M0.3 | short description]"
effort: xhigh
model: opus
---

Implement `$ARGUMENTS` from `docs/plan.md`. Be fully autonomous: the only point where the
user intervenes is after the draft PR is posted. Never ask the user to validate the plan.

Hard rules, from the repo:

- **No `git-approve`, no `/commit-review`.** Plain `git commit`.
- **`lib/postgrest/` core is human-written** (`lib/postgrest/AI_POLICY.md`). Agents may write
  its tests, dune/opam files and a codegen module, never its library code. If a step needs a
  change there, stop at the end with a precise description of the change and let the user make it.
- **Docs are the spec**: `docs/plan.md` (the step and its "Done:" criterion), `docs/layout.md`
  (where files go, dependency direction), `docs/architecture.md` (data model, protocols),
  `docs/style-guide.md` (how OCaml is written), the design handoff for screens. Concrete places
  and species in the handoff are placeholders.
- **"How do I" is a question**, not an instruction (memory rule). This skill is only invoked on an
  explicit "implement ...".

# 0. Workspace

Running locally: lease a worktree so the user's checkout, editor and `dune build @check --watch`
are untouched, and so `_build` (and its lock) are yours:

```sh
WT=$(treehouse get --lease --lease-holder "implement $ARGUMENTS")   # prints the path
cd "$WT"
```

If `treehouse.toml` is missing at the repo root, run `treehouse init` once and commit it. The dune
shared cache makes the locked packages (compiler included) restore in a fresh worktree instead of
rebuilding; the first `dune build` there still takes a minute or two. Release the worktree with
`treehouse return "$WT"` at the end, after the PR is posted.

Running in the cloud: work in place unless implementing several steps at once.

# 0b. Several steps, tickets or PRs at once

When asked to implement more than one thing ("implement M0.2 to M0.5", "do steps 6, 7 and 10",
"these three PRs"), do not run them one after another in this conversation and do not
interleave them by hand. Orchestrate them with the **Workflow tool**: this skill's instruction
is the explicit opt-in the tool requires. Load the `workflow-authoring` skill first, then write
a script in which **each step is one agent that runs this skill** (`/implement-workflow <step>`)
in its own leased worktree and on its own branch, so the worktrees, `_build` directories and
PRs never collide.

Shape of the script:

- Read the "Depends:" lines of the requested steps. Independent steps go in `parallel(...)`.
  A step that depends on another requested step goes after it in a `pipeline(...)`, and its
  agent is told to branch from the dependency's branch and to say so in its PR (stacked PR).
  A step that depends on an unrequested, unmerged step is reported back instead of started.
- Each agent gets: the step id, the base branch, the lease holder label, and the instruction
  to return a small JSON result (`{step, branch, pr_url, report_url, design_decisions,
  pushed_back, blocked}`) so the orchestrator never has to read the agents' transcripts.
- Keep the agent count to the number of steps plus the review and PR-text agents each of them
  spawns; that is within the session's workflow size guideline for up to four or five steps.
  For more, batch by milestone.
- After the workflow completes, one combined report (step 11) lists every PR with its design
  decisions, the pushbacks and the blocked steps, and the hourly loop watches the whole batch.

The same applies to several unrelated PRs or tickets from another tracker: one agent per unit
of work, parallel when independent, pipelined when stacked, always through this skill so each
one gets the plan, the red/green split, the review and the draft PR.

# 1. Context and scope

Read the step(s) in `docs/plan.md`: the text, the "Depends:" and the "Done:" criterion. Read the
neighbouring steps to know what is deferred to them: that is the out-of-scope list. Read the
sections of `layout.md`, `architecture.md` and `style-guide.md` the step points at. Check the
step's dependencies are done (`git log`, the files exist); if one is not, say so in the final
report and either implement the minimum stub it needs or stop, depending on size.

# 2. Branch

```sh
git fetch
git switch -c <type>/<step>-<slug> origin/main      # e.g. feat/m0-2-main-and-domain-tests
```

`<type>` is `feat`, `fix`, `chore`, `docs`, `test`, `refactor`, `ci`, `build`. `<step>` is the
plan step in lower case, `m0-2`, or a range `m0-2-3`. If a step depends on an unmerged branch,
base on that branch and say so in the PR.

# 3. Plan

Write a detailed implementation plan (a Plan agent is fine) to `.implement/plan.md`
(gitignored). It must be precise enough that the test writer needs no production code:

- every module and file to create or change, with its place in `layout.md`;
- every public signature (`.mli` level: types, `val`s with labelled arguments), and for each
  function its effects and error cases (`result` variants, exceptions it must not raise);
- the dune stanzas and dependency direction;
- the "Done:" criterion of the step turned into checkable assertions;
- what is explicitly out of scope.

**Design decisions are surfaced, never buried.** Any structural choice the step text does not
settle (a new module, a type shape, a protocol detail, a deviation from the docs) goes into a
`## Design decisions` section of the plan, each with what the docs say, why it does not fit as
is, and the options rejected. These are repeated verbatim in the final report and in a PR
comment (step 10). A choice that contradicts `stack.md`, `architecture.md` or `layout.md` is the
one case to stop and ask the user before continuing; everything else you decide.

# 4. Red and green, in parallel

Launch the **test-writer agent** (`.claude/agents/test-writer.md`) in the background with the
plan: it writes the tests from the signatures in the plan, not from the code, so the tests are
red until the implementation exists. Native alcotest for anything without a Brr dependency
(`domain`, `lib/postgrest`, `refs`); device-only layers get the manual check the step's "Done:"
line describes, written down as a checklist in the plan.

While it runs, **implement** the plan yourself. Follow `style-guide.md`. Write `.mli` files
first, from the plan, then the `.ml`. Run `dune build @check` often. Do not read or edit the
test files the agent is writing until it reports back.

# 5. Reconcile

Run `dune build` and `dune test`. Then run the **test-reviewer agent** on the new tests.

For every test that disagrees with the implementation, decide which one is right against the
plan. An implementation detail or a plain mistake on either side gets fixed. Anything else, a
behaviour the plan left open or where the test writer read the plan differently, is a design
decision: resolve it, record it in the plan's `## Design decisions`, and it goes to the report.

Everything must be green before step 6. `dune fmt` on the touched files (the repo's
`.ocamlformat` is the style; the AI-policy rule means never reformatting `lib/postgrest/` sources
you did not write).

# 6. Review

Run `/review` in Mode A against `origin/main` (or the base branch). It launches the lens agents
that match the changed paths, including `scope` and `comment-hygiene`, verifies contested
findings and calibrates severity. Do not fix while it runs.

# 7. Fix

Fix every finding you agree with, one commit per coherent cluster. Push back on a finding only
with a reason you would defend in the PR; the pushbacks are listed in the report and posted as
a PR comment (step 10). Re-run `dune test` after the fixes.

# 8. Re-run scope and comment hygiene

Run the `scope` and `comment-hygiene` lenses again on the fixed branch (the fixes often add
comments and sometimes drift from the step). Fix what they report. Stop iterating when both
return nothing above `nit`.

# 9. PR text

Have an **independent agent** that did not take part in the implementation read the full diff,
the plan step text and `.implement/plan.md`, and write the PR title and body following
`.claude/skills/push-pr/SKILL.md`: short, plain, What / Why / How / How to test. It must not
invent test steps: if a change has no checkable effect yet, it says so.

# 10. Draft PR

Push the branch and open the PR as a **draft** with `gh pr create --draft`. Then post, as PR
comments, in this order:

1. the design decisions, under the warning banner:
   ```markdown
   > [!WARNING]
   > **Design decisions taken without review.** Read these before the code: each one is a choice the reviewer did not make.
   ```
2. the review findings pushed back on, with the reason;
3. any question left open, and any step dependency that was stubbed.

One comment per group; none if a group is empty.

# 11. Report

Build the HTML report (`/lavish` or an artifact): the step and its "Done:" criterion with the
evidence it is met, the design decisions first, the test summary (counts, what is covered
natively, what needs the device), the review summary (findings fixed, pushed back, dropped),
links to the PR and its comments, and what the next step is. Then release the worktree.

# Background behaviour

- Run a `/loop` every hour that checks whether the autonomous part finished (PR posted, report
  built) and resumes it after an error, a killed process or a timeout. Stop the loop once the
  report is delivered.
- Every morning, or whenever waiting on the user, rebuild the report from `/wgo`: what was done,
  what is left, what is blocked, what needs a decision, what was raised and not answered.

# Notes specific to this repo

- `dune build` from a clean clone fetches and compiles the locked packages including OCaml;
  in CI that is cached under `_build/_private`, keyed on `dune.lock/`.
- A `dune build @check --watch` holds the build lock; in a leased worktree this is not an issue.
  In place, stop the watch before `dune test` and say so.
- The PostgREST integration fixtures are recorded by `scripts/record-postgrest-fixtures.sh`
  against Docker; re-record rather than hand-edit `test/postgrest/fixtures/scenarios.json`.
- Supabase schema changes are hand-written migrations plus the per-object dump from
  `uv run supabase/scripts/schema-dump.py` (needs the local stack); both go in the same commit.
