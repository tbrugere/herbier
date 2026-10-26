# Herbier

Personal Android app to record plants (single user).

## Docs

- `docs/stack.md` — chosen stack per layer and the reality check on the
  original idea. Decisions live here.
- `docs/architecture.md` — data model, local/remote schema, sync, photo and
  reference pipelines, link interception, planned spikes.
- `docs/style-guide.md` — how OCaml is written here. Follow it.
- `docs/layout.md` — what goes where in the repo (dune libraries, web, android).
- `docs/plan.md` — ordered milestones and steps to reach the mockup.
- `docs/design_handoff_herbier/README.md` — Claude Design handoff (screens,
  tokens). Concrete places/species in it are placeholders, not requirements.
- `docs/exploratory_research/` — dated research reports the decisions rest on.
- `docs/notes/` — primers and working notes (e.g. ocaml-react).
- `docs/claude-design-prompt.md` — the prompt given to Claude Design.

## Workflow

- This project does **not** use the `git-approve` gate / `/commit-review`
  skill. Commit directly with plain `git commit`.
- `/implement-workflow <step>` runs a plan step of `docs/plan.md` end to end: plan,
  tests written in parallel by the `test-writer` agent (red), implementation
  (green), `/review`, fixes, draft PR with a design-decisions comment, report.
  See `.claude/skills/implement-workflow/SKILL.md`.
- `/review` is the parallel, path-gated review (lenses under
  `.claude/skills/review/`, including `scope` against the plan step and
  `comment-hygiene`). `/push-pr` opens the draft PR with the title and body
  conventions.
- `lib/postgrest/` library code is human-written (`lib/postgrest/AI_POLICY.md`):
  agents write its tests, build files and codegen only. When a step needs a
  change there, describe it and let the user make it.
- "How do I ..." is a question to answer, not an instruction to act on.
