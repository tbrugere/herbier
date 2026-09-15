# Herbier backend: Supabase free tier, auth, schema, offline sync, device storage

Date: 2026-09-15

## Summary

**Recommendation (one user, minimal ops).** Build local-first: native SQLite on the device (`@capacitor-community/sqlite` or `cordova-sqlite-storage`) is the source of truth, previews go to the app-private filesystem, and Supabase Free is a sync/backup target reached through PostgREST with a hand-rolled outbox. Recording never depends on the server, so pausing is a nuisance, not data loss. Skip Pro ($25/mo): it only buys "never paused" and 7-day backups. One GitHub Actions cron running `supabase db dump` twice a week into a private repo both backs up and keeps the project alive.

**Supabase Free, 2026 (supabase.com/pricing, fetched 2026-09-15):** 500 MB DB (shared CPU, 500 MB RAM), 1 GB storage (50 MB max/file), 5 GB egress + 5 GB cached, 50k MAU, 500k edge-function invocations (150 s wall-clock, 2 s CPU), 200 realtime connections, 2 active projects, no backups, 1-day logs, image transformations Pro-only. Pausing: "considered inactive if it does not receive sufficient user database activity over the past week"; "a few user requests to the database each day" suffice; restore in one click for up to 1 year, data intact; after that, manual restore from a downloaded backup. Paid projects never pause. Official docs list only user activity (dashboard, API, app); community guides (2025–2026) report internal pg_cron does not count — UNVERIFIED by Supabase staff, so assume an external ping is required. No official Free-plan quota change found for 2025–2026. pg_cron and PostGIS are available on Free.

**Alternatives:** Neon Free (0.5 GB/project, 100 CU-h/month, scale-to-zero after 5 min, no pausing, PostGIS/pg_trgm/unaccent) is the best "Postgres without pausing" option but has no PostgREST/Storage. Turso Free (5 GB): browser sync still "planned". PocketBase needs a VM: Fly.io has no free tier anymore; Oracle Always Free reclaims idle instances. Fully local + Google Drive `drive.appdata` backup (non-sensitive scope) is the zero-server option.

**Auth:** email+password with sign-ups disabled is simplest. Google sign-in works via OAuth redirect + custom-scheme deep link (`herbier://auth` in Additional Redirect URLs, Android intent-filter, `exchangeCodeForSession` on `appUrlOpen`), or natively via Credential Manager + `signInWithIdToken` (no browser, no Drive token). Drive scopes can ride along (`scopes` + `access_type=offline&prompt=consent`), but Supabase does not store or refresh `provider_refresh_token` — store it yourself. Google Photos Library API only exposes app-uploaded media since 2025-03-31; full-library browsing needs the Picker API. RLS: `using ((select auth.uid()) = owner_id)` with `to authenticated` and an index on `owner_id`; anon gets no policies. Call `startAutoRefresh()/stopAutoRefresh()` on resume/background; use Preferences-backed session storage.

**Schema:** PostGIS `geography(Point)` + GiST, `st_dwithin(loc, pt, 500)` in RPC functions; `reference jsonb` + `reference_fetched_at`; tags as `text[]` (GIN) or a join table; names with a `pg_trgm` GIN index over `immutable_unaccent(lower(name))` for French. Keep thumbnails local; optionally mirror previews to a private Storage bucket.

**Sync options (2026):**

| Option | Free? | Plain JS in WebView | Server-side needs | Needs unpaused project | Verdict |
|---|---|---|---|---|---|
| PowerSync | Cloud free: 2 GB/mo, deactivated after 1 week idle; Open Edition self-host | yes (wa-sqlite; Capacitor SDK → native SQLite) | publication + replication role, WAL growth warning on idle Supabase | yes (two services pause) | overkill |
| ElectricSQL | <$5/mo waived (~5 M writes) | yes | logical replication; read-path only, you build writes | yes | read-only sync, skip |
| RxDB + Supabase plugin | core + replication free; SQLite/OPFS/IndexedDB storages $99/mo | yes | `_modified` trigger, `_deleted`, realtime publication | for pull only | good engine, evictable free storage |
| WatermelonDB | MIT | RN-first | pull/push RPCs, `last_pulled_at` | for sync only | awkward from OCaml |
| Legend-State v3 | MIT, still beta (June 2026) | React-flavoured | `created_at/updated_at/deleted` | for sync only | skip |
| Hand-rolled outbox | $0 | trivially, from OCaml | uuid PK, `updated_at` via `moddatetime`, `deleted_at`, PostgREST upsert | only while syncing | **recommended** |

**Device storage:** Capacitor docs: the OS "will reclaim local storage from Web Views"; IndexedDB/localStorage data "will be lost eventually"; `persist()` is often a no-op in Android WebView. OPFS via wa-sqlite needs no COOP/COEP but is still WebView site data. Use native SQLite plus `Filesystem` `Directory.Data` for previews.

**Top links:** pricing https://supabase.com/pricing · pausing https://supabase.com/docs/guides/platform/free-project-pausing · backups via GitHub Actions https://supabase.com/docs/guides/deployment/ci/backups · Capacitor storage eviction https://capacitorjs.com/docs/guides/storage · SQLite-on-web state (2026-05-15) https://powersync.com/blog/sqlite-persistence-on-the-web

---

# Detailed findings

Every claim cites a URL and, when known, the date of the source. Items not confirmed from a primary source are marked **UNVERIFIED**. Context: one user, Android, Cordova/Capacitor WebView, OCaml (js_of_ocaml) front, hundreds of plants / ~1k observations / a few thousand photos over years, reference JSON cache of a few KB per plant plus ~300 px thumbnails.

## 1. Supabase free tier (as of 2026) and alternatives

### 1.1 Free plan numbers (official pricing page, fetched 2026-09-15)

Source: https://supabase.com/pricing

| Item | Free | Pro ($25/mo) |
|---|---|---|
| Price | $0 | from $25/month + usage; includes $10/month compute credits (covers one Micro instance) |
| Database | 500 MB, shared CPU, 500 MB RAM | 8 GB disk included, then $0.125/GB |
| File storage | 1 GB | 100 GB, then $0.0213/GB |
| Egress | 5 GB + 5 GB cached | 250 GB + 250 GB cached |
| MAUs | 50,000 | 100,000 |
| Edge function invocations | 500,000 | 2 million |
| Realtime concurrent connections | 200 | 500 |
| Projects | 2 active | unlimited |
| Pausing | paused after 1 week of inactivity | never |
| Backups | none | daily, kept 7 days |
| Log retention | 1 day (API/DB), 1 h (auth audit) | 7 days |
| Spend cap | n/a | on by default |

Storage upload size: Free 50 MB max per file, Pro 500 GB (https://supabase.com/docs/guides/storage/uploads/file-limits, fetched 2026-09-15). Storage image transformations (server-side resizing) are **Pro and above only** ("Image Resizing is currently enabled for Pro Plan and above", https://supabase.com/docs/guides/storage/serving/image-transformations, fetched 2026-09-15).

Edge functions limits: 256 MB memory, 2 s CPU time per request, wall-clock 150 s on Free vs 400 s on paid, 100 functions per project on Free (https://supabase.com/docs/guides/functions/limits, fetched 2026-09-15).

There is no $10/month plan: the "$10" is the compute credit included in Pro. For one user the Pro plan's only real benefits are: no pausing, daily backups, image transformations, 7-day logs.

### 1.2 Inactivity pausing (the crucial part)

Official doc: https://supabase.com/docs/guides/platform/free-project-pausing (fetched 2026-09-15)

- "A Free plan project is considered inactive if it does not receive sufficient user database activity over the past week." "A few user requests to the database each day over the previous week is enough."
- Warning email about a week before; pause after 7 days of inactivity.
- Activity that counts per the doc: visiting the project in the Dashboard, API calls to the project, requests from the connected app.
- Restore: "You can restore a paused project for up to 1 year after it was paused" via Dashboard → Resume project. "The project will return to its previous state, including data and configurations."
- "Paid projects cannot be paused and are not subject to pausing for inactivity."
- Restore after more than 1 year: one-click restore is gone; you download the DB backup + storage files from the project overview, create a new project, restore with psql and the CLI (https://supabase.com/docs/guides/troubleshooting/restore-project-after-90-days-pause, fetched 2026-09-15; the URL slug says "90 days" but the page content now says "more than 1 year"). "Once a project is deleted, all associated data including backups is permanently removed."
- Third-party guides (simplebackups.com, 2026) claim one-click restore is disabled after 90 days paused — **UNVERIFIED / conflicts with the official page**, which says 1 year. Treat 90 days as the safe planning horizon anyway.

Does pg_cron / internal activity prevent pausing?
- The official doc lists only *user* activity (dashboard, API, app requests). It never says internal jobs count.
- Multiple 2025–2026 community guides state that internal pg_cron jobs do **not** keep a project alive and that the request must actually hit Postgres (e.g. `/auth/v1/health` does not count because it does not touch Postgres): https://levelup.gitconnected.com/supabase-free-tier-will-pause-your-app-heres-the-github-actions-fix-8c1fd35b49ca , https://shadhujan.medium.com/how-to-keep-supabase-free-tier-projects-active-d60fd4a17263 (2026), https://dev.to/krishna-builds-dev/how-to-keep-your-supabase-free-project-active-no-cost-cron-with-github-actions-1nnd . **UNVERIFIED by Supabase staff**, but consistent across sources; assume pg_cron alone does not count.
- Reliable keep-alive: an *external* scheduled request that runs a real query (GitHub Actions cron hitting PostgREST with the anon key on a tiny `keep_alive` table, or `supabase db` via psql). Reference implementation: https://github.com/travisvn/supabase-pause-prevention (Vercel cron → `/api/keep-alive` → SELECT on a table). Since a 2026 third-party blog reports "GitHub integration is now available on all plans including free, as of April 2026" (https://uibakery.io/blog/supabase-pricing) — **UNVERIFIED**; GitHub Actions calling the REST API never needed the integration anyway.
- pg_cron itself is available on all tiers ("Cron is only limited by the resources it uses", Supabase collaborator, 2025-07-23, https://github.com/orgs/supabase/discussions/37405).

Data risk from pausing: none while within the restore window; the project resumes with data intact. The risk is forgetting it for >1 year (or, conservatively, >90 days) and then having to do a manual restore, and the fact that Free has no automated backups at all. A paused project also means the app cannot sync until you press Resume in the dashboard (cold start ~10–30 s reported by third parties; UNVERIFIED number).

### 1.3 2025–2026 changes to the free plan

I found no official announcement of changed Free-plan quotas in 2025–2026; multiple 2026 roundups (uibakery.io, jetadmin.io, costbench.com) say 500 MB / 1 GB / 5 GB / 50k MAU / 2 projects / 7-day pause have not changed. Supabase's changelog is at https://supabase.com/changelog. The one relevant 2025–2026 doc change: the "restore after pause" page now says 1 year rather than 90 days.

### 1.4 Alternatives for one user

| Option | Free tier (2026) | Pausing / idle policy | Ops | Notes |
|---|---|---|---|---|
| Supabase Free | 500 MB DB, 1 GB storage, 5 GB egress, 2 projects | pauses after 7 days without user DB activity; restore ≤1 year | zero; needs keep-alive ping | PostgREST, Auth, RLS, PostGIS, Realtime out of the box; no backups |
| Neon Free | 100 projects, 0.5 GB storage/project, 100 CU-hours/project/month, 5 GB egress, 6 h PITR, scale-to-zero after 5 min (https://neon.com/docs/introduction/plans, fetched 2026-09-15) | no pausing, only cold start after scale-to-zero (seconds) | zero | Postgres only (no PostgREST/Auth/Storage bundled; Neon Auth exists "up to 60k MAU"); postgis/pg_trgm/unaccent/pg_cron available, but "pg_cron jobs will only run when your compute is active" (https://neon.com/docs/extensions/pg-extensions) |
| Turso Free | 100 DBs, 5 GB storage, 500 M rows read, 10 M rows written, 3 GB syncs/month, 1-day PITR; Developer plan $4.99/mo (https://turso.tech/pricing, fetched 2026-09-15) | no inactivity policy stated on pricing page | zero | SQLite-compatible; embedded replicas + offline writes exist for server/mobile SDKs, but "in-browser support is planned" (https://turso.tech/blog/turso-offline-sync-public-beta) — not usable from a WebView today. No auth/REST layer. |
| PocketBase self-host | free software; hosting: Fly.io has no free tier anymore (trial only; ~$2–5/mo for an always-on VM, https://www.saaspricepulse.com/blog/flyio-free-tier-2026); Oracle Always Free ARM VMs exist but idle instances (<20 % CPU/net/mem over 7 days) may be reclaimed (https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm) | Oracle reclaim risk | you run updates, TLS, backups | single binary, SQLite, auth + files built in. More ops than Supabase. |
| Fully local (SQLite on device) + backup to Google Drive appdata | $0 | none | none | No server, no pausing, no RLS. Drive `drive.appdata` scope is "non-sensitive" and the folder is hidden from the user (https://developers.google.com/workspace/drive/api/guides/appdata, fetched 2026-09-15). Loses: multi-device sync, server-side queries. |

Recommendation for one user who wants minimal ops:

1. Start **local-first** (SQLite on device is the source of truth — see §5), and treat the server as a backup/sync target, not as a dependency for recording. That makes pausing a non-event: if the project is paused, the app keeps working and syncs later.
2. Use **Supabase Free** as that target (you already know it; PostgREST + Auth + PostGIS + RLS with zero ops). Add a GitHub Actions cron (twice a week) that does a real `select` through PostgREST to avoid pausing, plus a weekly `supabase db dump` job to a private repo/Drive as the backup (Supabase's own doc: https://supabase.com/docs/guides/deployment/ci/backups).
3. Do **not** pay $25/month for one user unless you want daily backups and zero pausing risk without a keep-alive; $300/year buys nothing else you need. Neon is the closest "no pausing, real Postgres" alternative if the pausing dance annoys you, at the cost of no PostgREST/Auth/Storage.

---

## 2. Auth for a single-user app

### 2.1 Which sign-in

- **Email + password**: simplest and fully offline-testable; nothing platform-specific; no Google Cloud console. Disable sign-ups in the dashboard after creating your own user (or keep sign-ups on but lock data with an allow-listed user id in RLS, §2.4).
- **Google sign-in** from a WebView app has two routes:
  - **OAuth redirect (PKCE) with a deep link back**: `signInWithOAuth({provider:'google', options:{redirectTo:'herbier://auth', skipBrowserRedirect:true}})`, open the URL in the system browser/Custom Tab, add the scheme in Supabase Auth "Additional Redirect URLs" as `[YOUR_SCHEME]://[YOUR_HOSTNAME]`, declare an `intent-filter` with `<data android:scheme=... android:host=.../>` in the manifest, and on `appUrlOpen` call `exchangeCodeForSession(code)` (PKCE) — official deep-linking doc (https://supabase.com/docs/guides/auth/native-mobile-deep-linking, fetched 2026-09-15) covers Expo/Flutter/Kotlin but not Capacitor specifically; the Capacitor recipe is community-documented (Ionic forum thread 2023→Feb 2025: https://forum.ionicframework.com/t/setting-up-supabase-google-oauth-with-capacitor-android/234165 ; Chris Weed Feb 2026: https://cjweed.com/capacitor-supabase-social-auth-react/ ). Both community posts ended up using the *implicit* flow (`setSession` from the URL fragment) because PKCE needs the code verifier to be in the same storage that later handles the callback; with `flowType:'pkce'` you must make sure the client that started the flow (and its storage) is the one that handles `exchangeCodeForSession`, otherwise you get "both auth code and code verifier should be non-empty". Also reported: Google requires `prompt:'consent'`-style flows for the redirect to fire into the app, and some browsers do not open custom schemes from a redirect.
  - **Native Google Sign-In → `signInWithIdToken`** (Credential Manager on Android). Supabase's Google doc recommends this for native Android: no browser round-trip, needs a Web client id + Android client id (SHA-1) in Google Cloud (https://supabase.com/docs/guides/auth/social-login/auth-google, fetched 2026-09-15). Capacitor plugin: `@capgo/capacitor-social-login` with Supabase guide (https://capgo.app/docs/plugins/social-login/supabase/google/android/). Only an ID token is documented — no Drive access token.
- **Session refresh in a WebView**: supabase-js refreshes automatically with `autoRefreshToken:true`, but the docs say the loop runs continuously on non-browser platforms and recommends calling `startAutoRefresh()` on app resume and `stopAutoRefresh()` on background (https://supabase.com/docs/reference/javascript/auth-startautorefresh). Use a custom `storage` adapter backed by Capacitor `Preferences` rather than `localStorage` (WebView localStorage is evictable, §5). Community example: https://www.answeroverflow.com/m/1331272769459060746 .

### 2.2 Can the same Google sign-in give Drive/Photos scopes?

Yes, but with caveats (official doc https://supabase.com/docs/guides/auth/social-login/auth-google and https://supabase.com/docs/guides/auth/social-login, fetched 2026-09-15):
- Add `scopes: 'https://www.googleapis.com/auth/drive.appdata'` (or `drive.file`) and `queryParams: {access_type:'offline', prompt:'consent'}` to `signInWithOAuth`; then the returned session contains `provider_token` and `provider_refresh_token`. "Google does not send out a refresh token by default", hence the params.
- **Supabase does not store or refresh provider tokens.** After the Supabase session refreshes, `provider_token`/`provider_refresh_token` disappear from the session (https://github.com/supabase/auth-js/issues/806 ; https://github.com/orgs/supabase/discussions/22653). You must capture `provider_refresh_token` at sign-in, store it yourself (e.g. Capacitor Preferences / a private table), and exchange it against `https://oauth2.googleapis.com/token` yourself to mint Drive access tokens. For a personal app this is fine.
- The native ID-token route does not give Drive tokens; for Drive scopes you need the OAuth-redirect route (or a separate Google OAuth flow via a plugin).
- **Google Photos**: since 2025-03-31 the Library API can only upload (`photoslibrary.appendonly`) and read/edit **app-created** media (`photoslibrary.readonly.appcreateddata`, `photoslibrary.edit.appcreateddata`); broad `photoslibrary.readonly` is gone; selecting from the user's library needs the Picker API (https://developers.google.com/photos/support/updates, https://developers.googleblog.com/en/google-photos-picker-api-launch-and-library-api-updates/). So "photos stored in Google Photos" is workable only if the app itself uploads them (then it can list its own uploads). Also the Photos scopes are *sensitive* and need OAuth verification for production, whereas `drive.appdata` is non-sensitive.
- Drive `drive.appdata` folder: hidden from the user and from other apps; files cannot be shared/moved/trashed (https://developers.google.com/workspace/drive/api/guides/appdata). Good for backups/photos the app owns, bad if you want to browse them in Drive; use `drive.file` for a visible "Herbier" folder instead.

### 2.3 Recommendation

Email+password on Supabase (one user, sign-ups disabled) is the least moving parts. If you want Google Drive for photos, do a *separate* Google OAuth (Capacitor plugin or the same PKCE redirect trick against Google directly) and store the refresh token yourself; do not couple Supabase login to Drive tokens because Supabase drops them at refresh.

### 2.4 RLS for one user

Official guidance (https://supabase.com/docs/guides/database/postgres/row-level-security, fetched 2026-09-15): use `(select auth.uid()) = owner_id` (the sub-select caches the value per statement), name the role in `to authenticated`, and index `owner_id` (must be first column of a btree). Two acceptable patterns:

```sql
-- pattern A: owner column (future-proof for a second user)
alter table plants enable row level security;
create policy plants_owner on plants
  for all to authenticated
  using ((select auth.uid()) = owner_id)
  with check ((select auth.uid()) = owner_id);
create index on plants (owner_id);

-- pattern B: single allowed user, no owner column
create policy plants_me on plants
  for all to authenticated
  using ((select auth.uid()) = '<your-uuid>'::uuid)
  with check ((select auth.uid()) = '<your-uuid>'::uuid);
```

Pattern A with `owner_id uuid not null default auth.uid()` costs nothing and keeps the door open for a second account. Either way, keep the anon role without any policy so the public anon key (which is embedded in the APK) cannot read anything.

---

## 3. Schema recommendations

### 3.1 PostGIS

- Available on all plans; enable with `create extension postgis with schema "extensions";` (https://supabase.com/docs/guides/database/extensions/postgis, fetched 2026-09-15). The guide uses `extensions.geography(POINT)` columns, a GiST index, `<->` for ordered nearest-neighbour (uses the index in `order by`), `st_distance`, and recommends exposing nearby queries as SQL functions called via `rpc()`.
- For "plants seen within 500 m": `where st_dwithin(location, st_point(lng,lat)::geography, 500)`; store `accuracy_m real` alongside. For clustering at map zoom levels, `ST_ClusterDBSCAN` or `ST_SnapToGrid` in an RPC, but with ~1k observations you can cluster client-side.
- Neon also has PostGIS (§1.4); Turso/SQLite would need SpatiaLite or plain bounding-box math.

### 3.2 JSONB, tags, names

- `plants.reference jsonb` for the cached GBIF/etc. snapshot (a few KB) plus `reference_fetched_at timestamptz`. Use a GIN index only if you query into it; otherwise none.
- Tags: a `tags` table + `plant_tags(plant_id, tag_id)` join, or a `text[]` column with a GIN index. For one user with a few dozen tags, `text[]` is simpler and PostgREST supports `cs` (contains) filters; a join table is better if tags carry colour/description.
- Names: `names jsonb` or a `plant_names(plant_id, name, lang, kind)` table. For search over French vernacular names use `pg_trgm` + `unaccent`: both are standard Supabase extensions (the Supabase docs page for pg_trgm returned 404 during this research — **UNVERIFIED URL**, but the extension is confirmed in use on Supabase, e.g. https://github.com/supabase/supabase/issues/30503). Pattern: create an `immutable_unaccent(text)` wrapper (unaccent is STABLE and cannot be used directly in an expression index), then `create index on plant_names using gin (immutable_unaccent(lower(name)) gin_trgm_ops)` and query with `ilike`/`%` (https://github.com/orgs/supabase/discussions/5435 ; https://neon.com/docs/extensions/unaccent). Full-text search with a `to_tsvector('french', ...)` generated column + GIN is documented at https://supabase.com/docs/guides/database/full-text-search; trigram is better for partial/misspelled species names.

### 3.3 Thumbnails: Supabase Storage vs local only

- Free tier: 1 GB storage, 5 GB egress/month, no image transformations (Pro only). A few thousand ~50–100 KB thumbnails is ~200–400 MB — fits, but every full re-sync on a new device eats egress.
- Recommendation: keep *originals* wherever they live (Drive/Photos/device), generate ~300 px previews **on device** (canvas in the WebView or a native plugin), store them in the app-private filesystem (§5), and optionally mirror previews to a private Supabase Storage bucket as the cross-device cache. Reference-data thumbnails from GBIF/etc. can just be re-downloaded from their source URL, so cache them locally only and store just the URL in `reference`.

---

## 4. Offline-first sync from a WebView to Supabase (2026)

| Option | Cost (2026) | Runs in plain JS / WebView? | Local store | Server-side requirements | Needs project unpaused? | Verdict for Herbier |
|---|---|---|---|---|---|---|
| **PowerSync** | Cloud Free: $0, 2 GB synced/mo, 50 peak clients, 500 MB hosted, 2 instances, **"Free projects are deactivated after 1 week of inactivity"** (https://powersync.com/pricing, fetched 2026-09-15). Open Edition self-host is free source-available. | Yes: Web SDK is framework-agnostic (wa-sqlite in a worker, IndexedDB VFS default, OPFS optional); Capacitor SDK (2025-11-03) swaps to native SQLite via `@capacitor-community/sqlite` (https://powersync.com/blog/introducing-the-powersync-capacitor-sdk ; https://docs.powersync.com/client-sdks/reference/javascript-web) | SQLite (wa-sqlite or native) | Logical replication: `create publication powersync`, a `powersync_role` with `REPLICATION BYPASSRLS LOGIN`, JWT/JWKS config; writes uploaded by *your* `uploadData` via supabase-js; documented WAL-growth problem on idle Supabase instances (they suggest `max_wal_size`/`max_slot_wal_keep_size=1GB`) (https://docs.powersync.com/integration-guides/supabase-+-powersync) | Yes — both Supabase and PowerSync Cloud pause independently; replication slot on a 500 MB Free disk is a real risk | Overkill; two free services that both pause, plus a replication slot on a tiny disk. |
| **ElectricSQL** | Electric Cloud PAYG: bills under $5/mo waived (~5 M writes free), $1/M writes, Postgres Sync engine +$2/M emitted writes; reads free (https://electric.ax/blog/2026/04/02/electric-cloud-pricing, 2026-04-02). Self-host is open source. | Yes (HTTP shapes); site now redirects to electric.ax | your choice (PGlite, TanStack DB, etc.) | logical replication + publication; **read-path only**: "Electric does not do write-path sync" — you build the write API/queue (https://electric.ax/docs/guides/writes) | Yes (replication) | Read sync only; you still write the outbox yourself. Not worth it for one user. |
| **RxDB + Supabase replication plugin** | RxDB core Apache-2.0; replication plugins (incl. Supabase) are free; but the SQLite/OPFS/IndexedDB *storages* are Pro ($99/mo) — only Dexie/localStorage/memory storages are free (https://rxdb.info/premium/, fetched 2026-09-15; https://rxdb.info/replication-supabase.html, updated 2026-07-21) | Yes, plain JS | Dexie (IndexedDB) free; SQLite premium | table needs text PK, `_modified timestamptz` kept by `moddatetime` trigger, `_deleted boolean`, and the table in the `supabase_realtime` publication; RxDB engine handles retries/conflicts | Yes for pull/realtime; local writes queue offline | Solid engine, but the free storages live in evictable IndexedDB (§5) and it is a big dependency for an OCaml codebase. |
| **WatermelonDB** | MIT | React Native/SQLite oriented; web uses LokiJS/IndexedDB; sync protocol pull/push you implement as an RPC (https://supabase.com/blog/react-native-offline-first-watermelon-db) | SQLite (native) / LokiJS (web) | you write `pull`/`push` Postgres functions with `last_pulled_at` + `deleted_at` columns | Yes for sync only | React-Native-first; awkward from js_of_ocaml. |
| **Legend-State (`syncedSupabase`)** | MIT; v3 still **beta** as of June 2026 ("should be treated carefully for production use", https://community.legendapp.com/blog/post/legend-state-v3-JltsMZCqn91JgHu) | JS, React-centric but core is plain | IndexedDB/localStorage/AsyncStorage | tables with `created_at`, `updated_at`, `deleted` columns (`changesSince:'last-sync'`) (https://legendapp.com/open-source/state/v3/sync/supabase/) | Yes for sync only | Beta + React-flavoured; skip. |
| **Hand-rolled outbox** | $0 | Yes, trivially from OCaml | SQLite (native plugin) or IndexedDB | tables with `id uuid` (client-generated), `updated_at timestamptz default now()`, `deleted_at`; a `moddatetime` trigger; pull = `select … where updated_at > :cursor order by updated_at`, push = `upsert` with `Prefer: resolution=merge-duplicates` (PostgREST); last-write-wins by `updated_at` | Only when syncing; recording works fully offline | **Recommended.** ~200 lines: `pending_ops` table (op id, table, row id, payload, attempts), drain on connectivity, UUIDv7 ids, soft deletes, per-table cursor. One user/one device makes conflicts practically nonexistent; a second device later is handled by LWW on `updated_at`. |

Notes common to all: Supabase Realtime (Postgres Changes) requires adding tables to the `supabase_realtime` publication (https://supabase.com/docs/guides/realtime/postgres-changes) and is limited to 200 concurrent connections on Free — irrelevant for one user; you do not need Realtime for a one-user pull-on-open sync.

Why not PowerSync/Electric here: they solve fan-out to many clients with partial replication, at the cost of a replication slot on the source DB. On a 500 MB Free database with logical replication and a 2-minute `archive_timeout`, PowerSync itself documents runaway WAL on idle instances. For hundreds of plants and one phone, the outbox is strictly simpler and has no server-side moving parts beyond a trigger.

---

## 5. Local storage on the device (WebView)

- Capacitor's own guidance (https://capacitorjs.com/docs/guides/storage, fetched 2026-09-15): "The OS will reclaim local storage from Web Views if a device is running low on space"; for localStorage/IndexedDB "your app needs to expect that the data will be lost eventually"; use `Preferences` for small key/values and SQLite for real data. RxDB's Capacitor guide (updated 2026-07-21) says the same and recommends SQLite because it "stores the data on the filesystem of the device, not in the JavaScript runtime" (https://rxdb.info/capacitor-database.html). Real-world eviction report with `navigator.storage.persist()` being a no-op in Android WebView: https://github.com/super-productivity/super-productivity/issues/7901 (2025). Capacitor feature request for persisted storage was closed: https://github.com/ionic-team/capacitor/issues/7594.
- OPFS in the Android WebView: `navigator.storage.getDirectory()` works in Chromium WebViews on a secure origin (`https://localhost` in Capacitor), and wa-sqlite's OPFS VFSs (OPFSCoopSyncVFS, the new OPFSWriteAheadVFS of April 2026) do **not** need COOP/COEP; only sqlite-wasm's own `opfs` VFS needs those headers, which Capacitor cannot set (issue closed "not planned", https://github.com/ionic-team/capacitor/issues/7813, Dec 2024). Caveat: OPFS is still WebView-origin storage and lives under the same "site data" that Android can clear; device-specific OPFS blocking has been reported (https://www.lune.dev/questions/3454/why-does-android-webview-block-opfs-api-access-on-certain-devices). State of the art summary: https://powersync.com/blog/sqlite-persistence-on-the-web (2026-05-15).
- **Native SQLite via plugin** is the durable choice: `@capacitor-community/sqlite` (free, MIT; Android on androidx.sqlite + SQLCipher — which means you must declare encryption for Play export compliance even if unused; slow-ish on big DBs; IndexedDB on web) — critique from Capawesome, 2026-09-07: https://capawesome.io/blog/alternative-to-capacitor-community-sqlite-plugin/ ; Capawesome's own SQLite plugin is paid (Insiders). For Cordova: `cordova-sqlite-storage`. PowerSync chose `@capacitor-community/sqlite` for its Capacitor SDK (Nov 2025), a decent signal it is workable.
- **Image previews**: do not put 300 KB blobs into IndexedDB (eviction + Dexie/IDB blob handling on Android is the slow path). Write them as files in the app-private data directory with the Capacitor `Filesystem` plugin: `Directory.Data` is app-private and persists until uninstall; `Directory.Cache` may be purged under memory pressure; `writeFile` takes base64 for binary and large files may need `android:largeHeap="true"` (https://capacitorjs.com/docs/apis/filesystem, fetched 2026-09-15). Store only the relative path in SQLite. Cordova equivalent: `cordova-plugin-file` with `cordova.file.dataDirectory`. Display via `Capacitor.convertFileSrc(path)`.
- Sizing: a few thousand previews × ≤300 KB ≈ up to ~1 GB on device; fine in app-private storage, and only reference thumbnails need re-download.

---

## 6. Other things to know

- **Local dev + migrations**: `supabase init/start` runs the full stack in Docker; declarative schemas: put `.sql` files in `supabase/schemas/`, `supabase db diff -f name` generates a migration, `supabase migration up` applies locally, `supabase db push` deploys. Limits: diff does not capture DML, RLS policy *alterations*, view ownership, column privileges, comments, partitions (https://supabase.com/docs/guides/local-development/declarative-database-schemas, fetched 2026-09-15). For a solo dev this is the right workflow; keep RLS policies and triggers in a hand-written migration if the diff misses them.
- **Backups on Free**: none. Supabase's own recommended approach is a GitHub Actions cron running `supabase db dump --role-only`, `supabase db dump` (schema) and `supabase db dump --data-only --use-copy` and committing to a **private** repo (https://supabase.com/docs/guides/deployment/ci/backups). The same workflow doubles as the keep-alive (it queries the DB). Storage bucket files are not covered — mirror thumbnails elsewhere or treat them as re-creatable.
- **pg_cron**: available on Free; good for housekeeping (purging soft-deleted rows, refreshing reference data via `pg_net`) but assume it does not count as "activity" against pausing (see §1.2).
- **Edge functions**: 500k invocations/month, 150 s wall-clock on Free, 2 s CPU. A GBIF/POWO proxy with caching is easy (fetch → upsert into a `reference_cache` table with `fetched_at`), but since the app already caches the reference JSON per plant client-side, and GBIF is CORS-friendly, you likely do not need an edge function at all; add one only to hide an API key.
- **Capacitor's future**: Capgo's docs claim Ionic is "abandoning" Capacitor — but Ionic/OutSystems state Capacitor stays free, open source and maintained; Capacitor 8 shipped (SPM default on iOS) and Capacitor 9 is forecast for end of November 2026 (https://ionic.io/blog/the-road-to-capacitor-9, 2026-08-28; https://ionic.io/blog/important-announcement-the-future-of-ionics-commercial-products). Prefer Capacitor over Cordova for new work; Capacitor can load most Cordova plugins.
- **js_of_ocaml**: I found no published examples of js_of_ocaml + Capacitor; nothing structural prevents it (Capacitor is just a WebView plus a `window.Capacitor` bridge), but you will hand-write `Js.Unsafe` bindings for the SQLite/Filesystem/App plugins and supabase-js, or call PostgREST directly with `XmlHttpRequest`/`fetch` from OCaml, which is arguably simpler than binding supabase-js.

---

## Top links

1. Supabase pricing (Free/Pro numbers): https://supabase.com/pricing
2. Supabase project pausing policy: https://supabase.com/docs/guides/platform/free-project-pausing
3. Supabase GitHub-Actions backups (doubles as keep-alive): https://supabase.com/docs/guides/deployment/ci/backups
4. Capacitor storage guide (WebView eviction): https://capacitorjs.com/docs/guides/storage and Filesystem API https://capacitorjs.com/docs/apis/filesystem
5. PowerSync + Supabase requirements (replication, WAL warning) and pricing: https://docs.powersync.com/integration-guides/supabase-+-powersync , https://powersync.com/pricing
6. Supabase Google sign-in (scopes, provider tokens): https://supabase.com/docs/guides/auth/social-login/auth-google ; provider token not refreshed: https://github.com/supabase/auth-js/issues/806
7. Google Photos API restrictions since 2025-03-31: https://developers.google.com/photos/support/updates ; Drive appdata: https://developers.google.com/workspace/drive/api/guides/appdata
8. SQLite-on-web state (May 2026): https://powersync.com/blog/sqlite-persistence-on-the-web
9. RxDB pricing (which plugins are paid): https://rxdb.info/premium/ ; Supabase replication plugin: https://rxdb.info/replication-supabase.html
10. Electric Cloud pricing (2026-04-02): https://electric.ax/blog/2026/04/02/electric-cloud-pricing ; writes guide: https://electric.ax/docs/guides/writes
11. Neon plans: https://neon.com/docs/introduction/plans ; Turso pricing: https://turso.tech/pricing
12. Declarative schemas: https://supabase.com/docs/guides/local-development/declarative-database-schemas
13. PostGIS on Supabase: https://supabase.com/docs/guides/database/extensions/postgis
14. RLS performance pattern: https://supabase.com/docs/guides/database/postgres/row-level-security
