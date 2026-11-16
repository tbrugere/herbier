# Security review

Secrets and keys, untrusted input, and the few places where this app can be made to do
something its user did not ask for.

## Scope

Any changed code file, `.github/**`, the Android manifest, `capacitor.config.ts`,
`supabase/config.toml`.

## Checklist

- **Keys.** The Supabase publishable key (`sb_publishable_...`, formerly the anon key) may live
  in the app. The secret key (`sb_secret_...`, formerly `service_role`), a Google OAuth client
  secret, a Cloudflare token or any CI secret must never appear under `app/`, `web/`,
  `android/`, `www`, a test fixture or a committed `.env`. Detect: `sb_secret_`, `service_role`,
  `client_secret`, long base64 or JWT-looking literals, `secrets.` interpolated into a
  committed file.
- **Where keys are read from.** A key hard-coded in OCaml instead of injected at build time
  through the mechanism the step chose; a debug build that points at the production project.
- **The Pl@ntNet API key** (plan M9) is the user's, typed in 4m (« Clé API Pl@ntNet », decided
  2026-11-16): it lives only in Capacitor Preferences (`plantnet.api_key`), never built into the
  APK or read from a build variable, never in the SQLite `settings` table (backed up) or an outbox
  entry (synced), never in a commit, a test fixture or a log line, and shown masked in 4m. It rides
  in the identify request's query string (`api-key=`), so a log line, error message or dev page
  that prints that URL leaks it; fixture recorders must strip it.
- **Untrusted input from Android.** A URL or text arriving through the share target or an
  intent filter is attacker-controlled: it must go through `Domain.Link` classification before
  any network call, never be interpolated into a URL path, a SQL string or HTML, and the hosts
  it is matched against must be exact (`identify.plantnet.org`, not a `contains`).
- **Untrusted input from APIs.** GBIF, Wikidata, Wikipedia, Tela Botanica payloads are data:
  decoded by `refs/` into typed records (Pl@ntNet's identify answers by `identify/`, M9), never
  evaluated, never rendered as HTML (`innerHTML`, `El.set_prop El.Prop.inner_html`), image URLs
  restricted to the expected hosts and schemes before being loaded (`https://bs.plantnet.org/`
  for Pl@ntNet's images).
- **SQL built from strings.** Any query in `store/` that concatenates a value into the SQL
  text instead of binding a parameter, including `LIKE` patterns and FTS5 `MATCH` expressions
  (FTS5 query syntax must be escaped or quoted).
- **Files.** A filename derived from user or API data used in a `Directory.Data` path without
  being reduced to a safe token (path traversal); a preview written under a predictable name
  in a shared directory.
- **Row-level security** on the server is the only protection between users even though there
  is one user: a policy or grant that lets `anon` or another `authenticated` user read or
  write rows is `critical` impact (see supabase-db).
- **Google Drive.** The `drive.file` scope only; anything requesting `drive` or
  `drive.readonly`; tokens stored outside the encrypted preferences the step chose.
- **CI.** Workflow `permissions:` wider than needed; a secret echoed in a log; `pull_request_target`
  with checkout of the PR head; third-party actions not pinned.
- **Web view.** `allowMixedContent`, `webContentsDebuggingEnabled` or cleartext traffic enabled
  in `capacitor.config.ts` or the manifest outside a debug build; a `server.url` pointing at a
  dev machine in a committed config.

## Output

Write `.review-report/security.md`:

```
# Security review

## Findings
| Severity | Location | Issue | Suggestion |
| --- | --- | --- | --- |
| blocker/high/medium/low/nit | path:line | what's wrong | concrete fix |

## Questions for the author
- ...
```

Review only; no edits. Cite `file:line`. An empty table is fine.
