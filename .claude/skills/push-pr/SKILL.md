---
name: push-pr
description: Push the current branch and open a GitHub pull request following this repo's conventions (title format, What/Why/How/How to test, draft by default, design-decision comment). Use when the user asks to "open a PR", "push a PR", or when the implement skill reaches its PR step.
---

# Pushing a PR

## 1. Verify branch state

In parallel: `git status` (must be clean; if dirty, stop and ask whether to commit, stash or
discard), `git rev-parse --abbrev-ref HEAD`, `git log origin/main..HEAD --oneline` (must be
non-empty), `git diff --stat origin/main...HEAD`. Refuse on `main`.

## 2. Confirm the base

Default `main`. If `git log origin/main..HEAD` shows commits you did not make, or another branch
shares commits with HEAD that are not on `main` (`git merge-base` comparison), the branch may
be stacked: ask which base to use.

## 3. Push

`git push -u origin <branch>`. Retry up to four times with backoff on network errors only.

## 4. Title

`<type>(<scope>): <description> (<step>)`

- `<type>`: `feat`, `fix`, `chore`, `docs`, `test`, `refactor`, `perf`, `ci`, `build`, `style`,
  `revert`.
- `<scope>`: the library or area when localised (`domain`, `store`, `postgrest`, `ui`, `web`,
  `supabase`, `ci`).
- `<step>`: the plan step, `M0.2`, or a range `M0.2-3`. Omit when the PR has none.

Under 100 characters, imperative mood, lower-case first word, no trailing period. The title
becomes the squash commit subject on `main`.

Examples: `feat(domain): typed ids and records (M1.6)`,
`test(postgrest): replay recorded PostgREST exchanges`, `ci: cache dune package builds`.

## 5. Body

```
## What
<one paragraph>

## Why
<the problem this solves; the plan step and its "Done:" line>

## How
<approach; the non-obvious choices>

## How to test
<concrete steps a reviewer can follow; `dune test`, the manual device check from the plan>
```

Compose from the commit messages and the diff. Do not invent test steps: if a change has no
checkable effect yet, say so.

## 6. Open as draft

`gh pr create --draft --title ... --body-file ...`. The user flips it to ready after reading the
comments below.

## 7. Comments

Post as separate PR comments, each only if non-empty, in this order:

1. **Design decisions taken without review**, under the banner:
   ```markdown
   > [!WARNING]
   > **Design decisions taken without review.** Read these before the code: each one is a choice the reviewer did not make.
   ```
   One bullet per decision: what the docs or step said, what was done, why, what was rejected.
2. **Review findings pushed back on**, each with the finding, the lens, and the reason.
3. **Open questions and stubbed dependencies.**

Commit messages end with the attribution lines the session gives; PR bodies end with the
generation footer the session gives.
