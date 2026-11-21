# Herbier — Architecture proposal

Status: proposal, 2026-09-15. Companion to `stack.md` (which layer uses
what) and to the design handoff in `design_handoff_herbier/README.md`
(screens, tokens, the original data model). This file says how the pieces
fit and what the data looks like end to end.

## 1. Big picture

```
┌──────────────────────────── Android device ─────────────────────────────┐
│  Capacitor shell (Java: manifest intent-filters, plugins)              │
│  ┌───────────────────────── WebView ─────────────────────────────────┐  │
│  │  OCaml app (js_of_ocaml + Brr + react/ReactiveData)               │  │
│  │   ├─ UI (screens 4a–6k)            ├─ Reference pipeline (§6)     │  │
│  │   ├─ Store (local SQLite, §3)      ├─ Photo pipeline (§5)         │  │
│  │   ├─ Outbox / sync (§4)            ├─ Link resolver (§7)          │  │
│  │   └─ Map (MapLibre facade, §8)     └─ Identification (§12)        │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│  App-private files: previews/, originals/, reference thumbs/,           │
│  region.pmtiles                                                         │
│  WorkManager (Herbier's Uploader plugin): Drive uploads                 │
└─────────────────────────────────────────────────────────────────────────┘
        │ PostgREST (JWT)         │ Drive API (1h token)      │ GET, keyless
        ▼                         ▼                           ▼
  Supabase Free            Google Drive               GBIF · Wikidata · Tela
  (Postgres + RLS)         Herbier/<species>/…        INPN odata · Wikipedia
                           originals                  OpenFreeMap tiles
                                                      Photon / Géoplateforme
                                                      and, POST with a key:
                                                      Pl@ntNet identify (§12)
        ▲
        │ background job on the phone, every 12 h: light sync (push +
        │ one query) = keep-alive (no dumps; Supabase is the device's only copy)
```

Principles:

- **Device is the source of truth.** Every screen renders from local SQLite.
  The network is only used to sync, to fetch reference data, to upload
  originals, to draw map tiles outside the offline extract and to ask
  Pl@ntNet to identify photos (§12).
- **Nothing blocks on the network.** Recording, browsing, editing work
  offline; "Lier", reference search and refresh are disabled offline with a
  visible reason (handoff 4g/4i), and so is « Identifier » (6i, 6k; 6a left
  Noter on 2026-11-19, M8.75); an identification under way never holds Noter
  back.
- **One user, one owner id.** Multi-device is tolerated (LWW), not designed
  for.

## 2. Domain model

Same entities as the handoff, with three changes: `Photo.source` drops
`GOOGLE_PHOTOS` for now, `Plant.reference` becomes a separate table keyed by
source (so each source refreshes independently and cites itself), and every
row carries sync metadata.

```
Plant        id, display_name, aliases[], scientific_name?, authorship?,
             gbif_key?, notes, notes_updated_at? (null until first edit),
             cover_photo_id?, created_at, updated_at, deleted_at?
PlantRef     id, plant_id, source (gbif|wikidata|wikipedia|powo|ipni|taxref|
             tela|eppo|inat|plantnet), external_id, url,
             created_at, updated_at, deleted_at?; unique (plant_id, source)
Observation  id, plant_id? (null ⇒ « À identifier »), at, lat?, lon?,
             accuracy_m?, place_label?, place_derived?, note?,
             created_at, updated_at, deleted_at?;
             lat and lon both null or both set, accuracy_m only with them
Photo        id, observation_id, taken_at, width, height,
             sha256 (of the original as captured),
             preview_path (device), preview_bucket_key? (unused: the previews
             Storage mirror, M6.49, was dropped; always null),
             original_target (app_only|drive), drive_file_id?,
             upload_state (pending|uploaded|failed|original_missing),
             created_at, updated_at, deleted_at?
Tag          id, name, created_at, updated_at, deleted_at?
PlantTag     id, plant_id, tag_id, created_at, updated_at, deleted_at?;
             unique (plant_id, tag_id): re-adding a tag revives its row
Reference    id, plant_id, source, fetched_at, payload (one JSON object per
             source: each call's body, pruned to the fields read), status
             (complete|partial|missing|failed),
             created_at, updated_at, deleted_at?; unique (plant_id, source)
RefImage     plant_id, source, organ (flower|leaf|fruit|habit), remote_url,
             licence, attribution, thumb_path? (device, ~300 px); device-only;
             key (plant_id, source, organ)
```

Enum values are written as their stored labels (the `value` of a Postgres
lookup table, SQLite text): lowercase snake_case, each the snake_case of its OCaml constructor
(`Photo.Original_target`, `Photo.Upload_state`, `Reference.Source`,
`Reference.Status`, `Reference.Organ`). `Reference.Source` is shared by
`PlantRef`, `Reference` and `RefImage`. In OCaml, `PlantTag` is
`Tag.Plant_tag`, `PlantRef` and `RefImage` are `Reference.Plant_ref` and
`Reference.Image`; an observation's `lat`/`lon`/`accuracy_m` are one
`position option`. `accuracy_m` is null when unknown: no accuracy reported,
or the point was moved by hand (a manual move clears it).

Rules from the handoff that the model must keep: a plant may have zero
observations; an observation with no plant is "À identifier" and shows in
Journal and Carte only; free-name plants (`scientific_name = null`) are
valid and linking later fills `gbif_key`/refs and turns the free name into
an alias (the display name becomes the chosen row's French name, else its
Latin name; a relink of an already linked plant keeps its names and
aliases); deleting a photo in Herbier only unlinks, never touches Drive;
a Drive-side deletion becomes `original_missing` with the preview kept.

Derived, not stored: places. A "place" in the UI is a cluster of
observations within 500 m; a user-given name is written to `place_label` on
each observation of the cluster (handoff 4b). `Domain.Places.cluster` builds
them in one greedy pass in `(at, id)` order: each observation joins the
nearest cluster whose running centroid is within 500 m (inclusive; an exact
tie goes to the earliest cluster) or starts a new one, with no second pass.
Places are therefore stable under appends in time order only; a backdated
observation (photo import, edited time) can split or merge later places. A
place's or a day's name (4c) is `Places.label`: the most frequent trimmed
`place_label` (ties to the earliest), else likewise `place_derived`, else
the mean of the positions. Details in `app/domain/places.mli`.

## 3. Local store (device)

- `@capacitor-community/sqlite`, one database named `herbier` (the plugin
  stores it as `herbierSQLite.db`), unencrypted (single user, app-private
  storage), schema mirroring §2 plus:
  - `outbox(seq, table_name, row_id, op, payload_json, created_at, attempts,
    last_error)` — the sync queue.
  - `sync_state(table_name, last_pulled_at)`.
  - `settings(key, value)` — local, never synced. Keys are typed
    (`store/settings.ml`, a GADT; `store/settings.mli` is the full list):
    choices (`storage_target`, the `photo_original_target` label; the
    `wifi_only`, place-source and notice flags, `true` / `false`), and the
    Drive bookkeeping (`last_upload_at` and `drive_health_checked_at`,
    `Codec.timestamp` text; `drive_health_cursor`, a photo id;
    `drive_root_folder`, the Drive id of the photo root folder, non-blank
    text; `drive_root_folder_name`, that folder's name, non-blank text,
    « Herbier » when unset; local migration 6 (M7.79) turned a picked folder
    in force into that name and deleted the Picker's two keys).
    A value that does not parse is a decode error, not a silent default.
- Local column types (`store/schema.ml`, migration 1): ids, lookup values
  and text are `text`; timestamps are `text` in one fixed-width UTC format with
  microseconds (`Codec.timestamp`), so text order is time order; `text[]`
  and `jsonb` columns are `text` holding JSON, parsed back by
  `Codec.decode ~json` before `Postgrest.Row`; `double precision` is `real`.
  Foreign keys and the position checks mirror the server, except
  `plants.cover_photo_id` (it would close a cycle with `photos` and break a
  first pull). A cover that points at a deleted or not yet pulled photo is
  read as no cover: the plant's newest live photo stands in
  (`app/ui_model/cover.ml`). The four lookup tables (§2) exist locally too, with the same
  values (no `description`) and the same foreign keys, so an unknown label
  is rejected on the device; a value added later is a new local migration
  inserting its row, and `test/store` checks each table holds the
  `to_string` of every constructor. These local constraints are a hand-kept
  copy of the server's, checked only by `test/store`, not against
  `supabase/schema/`. The plugin enforces foreign keys on every open
  and they cascade on delete, so a local upsert is `insert … on conflict (id)
  do update set …`, never `insert or replace` / `replace into` (which deletes
  the old row first, taking its children with it). JSON values that are
  `null` and non-finite floats cannot be stored (they read back as SQL null).
  `RefImage` (§2) is not in migration 1: migration 3 (M4.37) creates its
  device-only table `ref_images` (`store/ref_images.ml`, not synced, no
  outbox entry, hard deletes) and the local lookup table `reference_organs`
  its `organ` column references. Migration 4 (M5.58) creates the device-only
  table `commune_packs` (`store/commune_packs.ml`: département code, name,
  file path, size, commune count, download time; not synced, hard deletes),
  one row per « IGN hors-ligne » pack. Migration 5 (M7.52) creates the
  device-only table `uploads` (`store/uploads.ml`: photo id (foreign key to
  `photos`, cascade), path, type, size, the resumable session's URL and start
  time (both or neither), attempts, last error, creation time; not synced,
  hard deletes), one row per original this install keeps for Drive. The schema version is SQLite's `user_version`; a file at a
  version above the app's is refused, not migrated. A migration is a list of
  statements (`Schema.migration`), applied with its `user_version` bump in one
  transaction by the plugin's `executeSet`, which prepares each string as
  given; the plugin's `execute` splits its text on `;` and newline, so it is
  used only for single statements.
- Files under `Directory.Data`:
  - `previews/<photo_id>.jpg` (≤1600 px, q0.7 or WebP), always present.
  - `refthumbs/<plant_id>/<source>-<organ>.jpg` (shorter side ≤300 px, JPEG
    q0.8), evictable via "Libérer" (4m « Données hors-ligne »): every
    `thumb_path` is cleared first, then `refthumbs/` is removed whole, so a row
    never points to a deleted file; it refuses while a thumbnail sync runs, and
    syncs asked meanwhile are skipped; the next fiche entry online downloads
    them again. A changed image for an organ overwrites
    the same file: the row's `thumb_path` is cleared first and set again only
    if the row still holds the downloaded URL (the syncs of one plant never
    overlap). The thumbnails of a deleted plant stay until "Libérer" removes
    `refthumbs/`.
  - `communes/<département>-<ms>.json`, an « IGN hors-ligne » pack
    (`Geo.Communes.to_string`: the communes of one département, rings
    simplified to 20 m, integer coordinates at 1e-5°). A new download writes
    a fresh path, then its row, then deletes the old file, so a row never
    points to a half-written file (a failed write or row deletes the new
    file; a crash in between leaves an orphan, for a later orphan sweep of
    `communes/` against `commune_packs`, not done: "Libérer" only removes
    `refthumbs/` whole); « Supprimer »
    deletes the row, then the file.
  - `originals/<photo_id>` (no extension: the type is in the `uploads`
    row), an original bound for Drive, kept from the save until it is in
    Drive or the photo is gone. Not the cache directory: Android may clear it
    before a Wi-Fi-only upload runs. The file is written before its row (a
    failed write or row deletes it again, and the photo goes `failed`); a
    crash in between leaves an orphan, for the same later orphan sweep of
    `originals/` against `uploads`.
  - `tiles/<region>.pmtiles`, downloaded once from Settings.
- The binding (`Cap_sqlite.query`) returns each row as the JSON text of the
  plugin's row object; `store_io/db.ml` parses it and decodes it with
  `Postgrest.Row`, so yojson stays out of `bindings/`. Single statements run
  in the plugin's per-call transaction; `Cap_sqlite` also binds
  `beginTransaction` / `commitTransaction` / `rollbackTransaction`, and a
  statement inside such a transaction passes `transaction = false` (with the
  plugin's own transaction it fails *and* rolls back the open one). So `Db`
  serialises every operation on a connection: each starts once the previous
  one settled, and a write started from another callback cannot land in the
  middle of a transaction.
- Every write to a synced row goes through `Db.edit` (M1.13): the per-table
  modules return `Outbox.edit` values (the statement, a read-back query by
  `id` or, for `plant_tags`, by `(plant_id, tag_id)`, and the table's
  `Postgrest.Input` encoding); `Db.edit` runs a list of them in one explicit
  transaction and, for each statement that changed a row, reads the row back
  and appends `outbox(table_name, row_id, op = 'upsert', payload_json)`
  where the payload is the stored row through `Postgrest.Input.to_json` (the
  upsert body push sends; the stored row, so a soft delete or a revived link
  carries its real id and `deleted_at`). A statement that changes nothing
  appends nothing; entries are never coalesced (rewriting an earlier entry
  could move a child's new foreign key ahead of its parent). Any error rolls
  back rows and entries together. `created_at` is SQLite's clock
  (`Codec.timestamp` format, milliseconds), for display only; order is `seq`.
  Settings, pull and the dev seed write without entries. The pull's and the
  seed's synced writes are `Outbox.bare` values (`Outbox.without_entry` of an
  edit, `Tags.upsert_plant_tag`, `References.upsert_row` /
  `upsert_plant_ref`), a type `Db.write` does not take (`Outbox.bare_stmt`
  unwraps it for `Db` and the tests only, a convention: the pure store
  modules cannot name `Db`): they run only inside
  `Db.bare_transaction` (one explicit transaction, `pragma defer_foreign_keys
  = on`, rolled back on any error), so the dev seed is atomic too. `seq` has
  no `autoincrement`, so a number may be reused once the newest entry is
  deleted: the sync engine must not hold a `seq` across a `delete`.
- IndexedDB/localStorage are used for nothing durable (Android evicts them).
- Full-text search over names is done locally (SQLite FTS5 with
  `unicode61 remove_diacritics 2`), so search works offline. The Postgres
  side has the equivalent pg_trgm/unaccent index for any future web client.
  Migration 2 creates `plant_search(plant_id unindexed, names, tags, places)`:
  one document per live plant keyed by the plant's id (not its rowid, which a
  `VACUUM`, a re-key or a table rebuild may renumber), holding its display
  name, scientific name and aliases, the names of its live tags (through live links), and the
  `place_label` / `place_derived` of its live observations. Triggers on
  `plants`, `plant_tags`, `tags` and `observations` rebuild the documents of
  the plants a write touches, so every writer (UI, seed, pull, cascade)
  keeps the index right.
  The query side (`Search.match_expression`) treats non-ASCII punctuation
  (NBSP, « », ’, …, dashes) as spaces, drops terms of symbols only, folds
  what was typed (ASCII case, Latin-1 accents), strips one French or Latin
  ending (`-es -is -us -um -ae`, else `-e -s -a -i`, keeping at least 4
  bytes) and prefix-matches each term
  quoted, so "digitale" finds both "Digitale pourpre" and "Digitalis".
  Results come in the Collection's order (`display_name collate nocase`),
  not by rank.

## 4. Sync (outbox to Supabase)

Postgres tables `plants, plant_refs, observations, photos, tags, plant_tags,
reference` with:

- `id uuid primary key` generated on device (UUID v7, so ids sort by creation time);
- `owner_id uuid not null default auth.uid()`, index, RLS
  `using ((select auth.uid()) = owner_id)` for `authenticated`, no anon
  policies;
- `updated_at timestamptz` set to server time by a trigger on every insert
  and update (below), `deleted_at timestamptz` for soft delete;
- `observations.loc geography(Point, 4326)` + GiST, kept in sync from
  `lat/lon` by trigger; an RPC `plants_near(pt, radius_m)` for "Vues ici" in
  the Noter screen (handoff 4d) when online, with a local Haversine fallback;
- `reference.payload jsonb`: the reference cache is synced like the other
  tables, so it is backed up, not refetched on a new device;
- the natural keys of §2 (`plant_refs`, `plant_tags`, `reference`) as unique
  constraints next to the `id` primary key: the store looks a row up by its
  natural key and reuses its `id`, so push upserts on the primary key `id` for
  every table (PostgREST's default conflict target; no `on_conflict` query
  parameter is sent) and the outbox keeps one `row_id` per row. A new row of
  these three tables gets an id derived from its natural key (UUID v5 of
  `plant_id` and `tag_id` or `source`, under the Herbier namespace
  `b85c6db9-9479-4fb1-af57-3ff6ad665b62`, of the name
  `<table>/<plant_id>/<tag_id or source>` in canonical lowercase, e.g.
  `plant_tags/<plant_id>/<tag_id>`; `Ids.Plant_tag_id.of_key`,
  `Ids.Plant_ref_id.of_key`, `Ids.Reference_id.of_key`), not a random one: two
  installs that create the same link before syncing produce the same id, so the
  second push merges instead of failing on the unique constraint;
- server-only columns, `owner_id` (defaulted to the caller) and
  `observations.loc` (set by the trigger), carry `metadata: server_only`
  in their column comment and are left out of the generated
  `app/store/tables.ml`: the app never sends or reads them;
- integer columns (`gbif_key`, `width`, `height`) stay `integer`, never
  `bigint`: under js_of_ocaml an `int` is 32 bits, and `Postgrest.Col`
  raises on a wider literal inside the select's future, which would leave
  the pull pending instead of failing;
- foreign keys are checked without RLS, so a row may reference another
  owner's row by id. Accepted: there is one account and sign-ups are off.

`updated_at` has no default and the device always sends it, as its local
last-write-wins clock, but the server's `set_updated_at` trigger replaces it by
server time (`now()`) on every insert and update. The pull cursor therefore
never compares a device clock: a row created offline and pushed hours later
still sorts after every other install's last pull. The push does not ask for the
row back (no `return=` preference; PostgREST's default is `minimal`): the device
adopts the server value at the next pull. `now()` is the transaction start, so a
long transaction can commit behind a cursor already advanced; the pull asks for
a few seconds of overlap (`updated_at=gt.<last_pulled_at - 5 s>`), which LWW
makes idempotent.

The local store keeps timestamps to the microsecond, as `timestamptz` does,
but `Postgrest.Col` encodes a `TimestampTz` with whole seconds
(`Ptime.to_rfc3339` without `~frac_s`), so until that encoder passes
`~frac_s:6` a pushed `created_at`, `at` or `notes_updated_at` loses its
fractional digits and the next pull brings back the truncated value.
`updated_at` is unaffected (the server sets it).

Protocol, run by `sync/engine.ml` on app start, on resume, after each local
write, on sign-in and when its retry timer fires. One cycle at a time
(`sync_core/cycle/schedule.ml`): a trigger during a cycle runs exactly one more after
it. A cycle pushes, then pulls only if the push completed (parked entries
do not stop it). A stopped cycle backs off (10 s doubling to 300 s); any
trigger but the timer runs at once, keeping the attempt count; going to the
background cancels the timer, and a cycle that stops after the app went to
the background arms none (the next resume runs at once). A 401 refreshes the
session before backing off; signed out, the engine stays idle until the next
sign-in. No online check: a failed fetch is a stop like any other.

1. **Push**: for each outbox row in `seq` order, one request per row,
   `POST /rest/v1/<table>` with `Prefer:
   resolution=merge-duplicates,missing=default` (upsert on `id`; one row per
   request so that a 4xx names exactly one entry and each row gets its own
   `now()`). On 2xx delete the outbox row. Statuses are classified by
   `sync_core/net/rest.ml`: 540 paused project (below); 401 unauthorized (refresh the
   session, never park); 408, 429 and 5xx transient (stop, retry later with
   exponential backoff); any other 4xx rejected (park it with `last_error`,
   the status, shown in Settings: the library's error carries no body). A
   network error is transient too. Foreign keys
   are not deferrable, so `seq` order (parents first) is load-bearing and a
   parked row also parks the rows that reference it.
2. **Pull**: per table, `GET …?updated_at=gt.<last_pulled_at - overlap>&select=<columns>&order=updated_at,id`
   with `Range-Unit: items` and pages of 500 rows (`Range: 0-499`, then
   `500-999`, …), below Supabase's `max_rows` (1000), so a full page means
   "ask for the next page" whatever the server's cap. The whole pull of a
   table keeps the same filter and moves only the `Range`: asking again from
   the last row's `updated_at` would return the same page forever when more
   than 500 rows share one `updated_at` window (one transaction stamps all
   its rows with one `now()`, and the bound is rendered in whole seconds), and
   a keyset cursor on `(updated_at, id)` needs the bound to the microsecond,
   which `Postgrest.Col` does not render yet. Offsets have one race: a row of
   an already-read page that another install updates during the pull moves
   to the end, so the rows behind it shift back by one and the first row of
   the next page is skipped. That row's id then comes back twice in the same
   pull; when a pull sees an id twice it keeps its old `last_pulled_at`, and
   the next cycle reads the window again. Each row is merged by
   `domain/merge.ml`: no local row → insert; a pending outbox entry (one
   that is not parked) → keep the local row (outbox wins: its push lands
   after this version and wins on the server; a parked entry never lands,
   so its row takes the remote version and the parked payload stays in the
   outbox, listed in Settings); equal to the local row (each entity's `equal`;
   `reference.payload` structurally, as `jsonb` reorders keys) → nothing;
   else the remote row replaces the local one. Last write wins in the server's
   order: the row the server returns is the last write any install pushed,
   stamped by the trigger, so the device's own `updated_at` (its clock until the
   next pull) is never compared with it; a device clock ahead of the server's
   would otherwise keep a stale row over another install's later edit, for good.
   This requires push and pull never to run at the same time, so that a pull
   never applies an answer older than a push already done. Update
   `last_pulled_at` to the greatest `updated_at` the table returned. Every table
   is fetched before anything is written, so the transaction never waits on the
   network. Local foreign keys are enforced, and a parent created elsewhere
   between the pull of its table and the pull of its child's table reaches the
   device after the child. So the tables are applied parents first (plants,
   tags, observations, photos, then the link and reference tables) in one
   transaction with `pragma defer_foreign_keys = on`; if a foreign key fails
   (`pragma foreign_key_check` just before the commit: on Android a failed
   commit leaves the transaction open and cannot be rolled back), the whole pull
   rolls back with its cursors and the next cycle, which now sees the parent,
   retries. Statuses are classified as for the push, except that a 4xx other
   than 401 on a select stops the cycle and is retried with backoff (there is
   nothing to park), and so is a page that does not decode (one bad row fails
   its table's select, and with it the pull). Such a stop recurs until the app
   or the server changes, so Settings shows the last
   cycle's as « Réception bloquée » (`Outcome.persistent`: another 4xx, an
   undecodable answer, a failed local write); the pull stays atomic, one bad
   table blocks every table.
3. Previews are not synced (no Storage bucket; M6.49 dropped 2026-11-12):
   a new device rebuilds them from the originals (Drive).

Pausing: Supabase answers HTTP 540 to every request for a paused project; the
outbox then just waits; the user sees "serveur en pause" in Settings with a link
to the dashboard. Recording is unaffected. 4m's « File d'envoi » card shows it
while the engine's last cycle stopped on `Paused` (`Engine.last`, re-read after
each cycle; nothing stored: after a restart the first cycle finds it again),
with `https://supabase.com/dashboard/project/<ref>` for a hosted
`<ref>.supabase.co` backend and no link for the local stack.

Keep-alive job (plan M6.50). A Free project is paused after a week without
« sufficient user database activity »; Supabase's docs say that requests
from the app count and that « a few user requests to the database each day »
usually suffice (quotes and links in plan.md, M6.50). So the phone itself
keeps the project up: `@capacitor/background-runner` has WorkManager run
`web/runner/keepalive.js` every 12 h (`interval: 720` in
capacitor.config.ts, `Keepalive.Wire.interval_minutes`; Doze may stretch it),
with a network, app closed or not. The script runs in the plugin's own JS
engine (no WebView, no OCaml, no SQLite: a fresh context per event, state in
`CapacitorKV`, the SharedPreferences file named after the runner's label).
One run: refresh its session when it expires within 90 s
(`Session.refresh_margin`; GoTrue's 4xx with a code drops it, anything else
keeps it for the next run; a session the app set or took during the refresh
stands, and the refreshed one is logged out), push the handed queue unless
the app is active, then one authenticated query, a select of
`tags` by the nil UUID (one index probe, `[]` whatever the data, so no
personal data in its log). It logs each run (`keepalive: …` in logcat, the
last 20 in its KV, shown on `#dev/keepalive`), never a token.

- Its own session. Refresh tokens rotate, so two holders of one session
  break each other (the second to refresh presents a revoked token and GoTrue
  revokes the family). At each sign-in `Auth` exchanges the same Google id
  token and raw nonce a second time (GoTrue keeps no record of used ones):
  a second, independent session, handed to the job (`setSession`) right
  after the previous job session is taken back (`takeSession`), in one step
  of the app's dispatch chain; the taken one is then logged out. A grant
  that answers after a sign-out, a revoke or another sign-in is logged out,
  and so is one the job could not take (no plugin, a failed dispatch), so
  that no live refresh token is left with nobody holding it. Sign-out and a
  revoked app session take the job's back too; a take that timed out is
  still followed, and the session it returns late is logged out. A take the
  plugin refused leaves the job its session (it keeps running as the same
  user) until the next sign-in replaces it. A failed second grant leaves the
  app signed in and the job without a session (its runs log `none`).
- The queue. The job pushes the app's pending outbox entries as requests
  the app rendered with the same `Net.Rest` code as the engine (a recording
  `Postgrest.Client.HTTP`), each with its bearer added, in `seq` order,
  stopping at the first failure; the app keeps its entries and the engine
  pushes them again (an upsert of the same payload is idempotent). The job
  must never push an entry once the engine has pushed a newer one of the
  same row: the server stamps every write newest, so the stale payload would
  win for good, and the next pull would then replace the local row with it
  too (no outbox entry protects it any more). Hence the engine hands the
  queue off at the end of each push (`Keepalive.hand_off`, when entries
  remain) and takes it back before the next one (`Keepalive.before_push`),
  the first push of every process included (a queue handed by an earlier
  process survives in the KV). A take-back that is not confirmed holds the
  push back (`Held "keep-alive: …"`, retried with backoff, not shown as
  persistent) while the pull still runs: it sends no write. A hand-off the
  plugin refused stored nothing and needs no take-back; one that timed out
  may have landed and does. The app's dispatches run one after the other,
  and the job re-reads its queue and the app state before each request. A
  request in flight is marked in the KV (`inflight`) before those checks,
  and `reclaim` answers only once none is (10 s at most: past that, the push
  is held and retried); a mark older than 10 minutes is a run that died. A
  queue pushed to the end is forgotten by the job, so it is not pushed again
  every run. The job sends its requests only under the backend's URL. The
  hand-off is not done on going to the background: Android shuts the runner
  down in the same `onStop` that fires `appStateChange`, so a dispatch made
  then always fails; a push still running at that moment hands off after the
  runner stopped, so the job has no queue until the next open (the entries
  stay in the outbox). Known limit: the runner's `fetch` has no timeout, so a
  request that hangs keeps its run waiting until WorkManager stops the
  worker, and its `inflight` mark holds the engine's push back for up to
  10 minutes.
- The job's KV is left out of Android's backups like `auth.session` (a
  refresh token), and the permissions the plugin merges in but the job does
  not use (background location, exact alarms) are removed in the app's
  manifest; POST_NOTIFICATIONS stays for ForegroundRunPlugin (§8).

Auth on device: Google sign-in via Credential Manager → Supabase's id-token
grant (supabase-js's `signInWithIdToken`) → session in Capacitor
Preferences, refreshed as below. No supabase-js: `sync/auth/server.ml`
makes GoTrue's three calls over fetch (`POST /auth/v1/token?grant_type=id_token`,
`grant_type=refresh_token`, `/logout?scope=local`) for `sync/auth/auth.ml` and
the keep-alive, described and decoded sans IO in `sync_core/auth/gotrue.ml`.

- Nonce: 32 random bytes as hex are the raw nonce, sent to GoTrue; their
  SHA-256 hex goes to the plugin, which puts it verbatim in the id token's
  `nonce` claim; GoTrue compares the claim with the hash of the raw nonce
  (`skip_nonce_check = false`). The plugin's `standard` style always shows
  the account chooser.
- Session: one Preferences key, `auth.session`, a versioned JSON object
  (`sync_core/auth/session.ml`), written before the in-memory session is replaced.
  Every write of the key (sign-in, refresh, sign-out, a revoked session)
  runs after the previous one has resolved, so a refresh that lands during
  a sign-in or a sign-out cannot write over it. A refresh rotates the
  refresh token: if the app dies between the server's rotation and that
  write, the next launch is signed out (one tap to sign in again; nothing
  is lost, the outbox is local). The key is left out of Android's backups
  (`android/app/src/main/res/xml/backup_rules.xml`,
  `data_extraction_rules.xml`): a refresh token does not go to Google
  Drive, and a reinstall starts signed out. The rule covers Preferences'
  whole file, so the Pl@ntNet API key kept there (§12) stays off backups too.
- Expiry: the session's `expires_at` is the device's clock when the request
  was sent plus GoTrue's `expires_in`, not GoTrue's `expires_at`, so that a
  device clock set wrong does not make every session due (a refresh loop)
  or late.
- Refresh: 90 s before the access token expires, by one timer while the app
  is in the foreground; on resume a due session is refreshed at once; the
  timer is cleared on background. A refresh that GoTrue itself answers 4xx
  (its JSON error, with a code; except 408, 429) drops the session (signed
  out); a network failure, 408, 429, 5xx or a 4xx that is not GoTrue's (a
  proxy's page, a gateway's 401 for a wrong key) keeps it and retries after
  10 s, doubling up to 300 s. A build with a wrong key or URL therefore
  retries forever (logged) rather than signing out. The PostgREST transport
  awaits `Auth.access_token` per request, which refreshes a due session
  first, and hands the token to a per-request `Client.supabase_conn`.
- The account is created by hand, before its first sign-in, with the same
  Gmail address and a confirmed email: sign-ups are off, and GoTrue links
  the Google identity to the existing user with that verified email. Locally:
  `curl -X POST "$API_URL/auth/v1/admin/users" -H "apikey: $SERVICE_ROLE_KEY"
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" -H 'Content-Type: application/json'
  -d '{"email":"<gmail>","email_confirm":true}'` (values from `npx supabase
  status -o env`); in production, the dashboard's Authentication → Add user,
  "Auto confirm", with Providers → Google enabled (client id = the Web client
  id, nonce check on) and "Allow new users to sign up" off.
- Where a build signs in is fixed at build time from `HERBIER_SUPABASE_URL`,
  `HERBIER_SUPABASE_PUBLISHABLE_KEY` and `HERBIER_GOOGLE_WEB_CLIENT_ID` (the
  Web OAuth client id, also `config.toml`'s Google `client_id`: export
  it before `npx supabase start`, and restart the stack after exporting it
  later; unset, the stack starts and refuses every Google id token).
  Outside the release profile the first two default to the local stack
  (`http://127.0.0.1:54321`, reached from the emulator through `adb reverse
  tcp:54321 tcp:54321`, which `scripts/emulator.sh start` sets up; the debug
  APK's network security config allows cleartext HTTP to loopback only); a build
  without all three shows « Connexion indisponible dans cette version. » in
  4m. Dev builds (`dune build`, `scripts/dev.sh`, `scripts/emulator.sh`)
  read no file and so get the local stack, unless the shell exports the
  variables (keep production values out of `.envrc`). Production builds go
  through `scripts/release.sh` (`--debug` for a debug APK of the same
  bundle), which loads the git-ignored `.env.prod` (from the committed
  `.env.prod.example`) for its own process only, or else takes the
  environment (CI), and refuses to build without all three values.
  A release is signed by the user's release key, kept outside the repo:
  `HERBIER_RELEASE_KEYSTORE`, `HERBIER_RELEASE_KEYSTORE_PASSWORD`,
  `HERBIER_RELEASE_KEY_ALIAS`, `HERBIER_RELEASE_KEY_PASSWORD`, which
  Gradle reads from the environment (all or none). Android updates an app
  in place, keeping its database and `files/`, only with the same
  application id, a versionCode not lower, and the installed certificate
  (or its successor in a rotation lineage); an uninstall deletes both. So:
  one application id for every build type; versionCode = the commit count of
  `main` at the merge base of HEAD and `origin/main`, versionName = `git
  describe`, for every build (a branch build carries the code of the `main`
  it starts from, never more than the next `main` build after the squash
  merge, so a release from `main` is never a downgrade; the emulator, where
  worktrees on older bases take turns, installs with `adb install -d`); and
  when the release key is set it signs the `--debug` build too, so the two
  replace each other in place (plain dev builds keep the default debug key).
  That `--debug` build is debuggable, so `adb shell run-as` reads its
  database and session: it stays on the user's machine and phone. An install
  signed with the previous key (this Mac's debug key, the phone's builds
  before M8.56) switches once by APK key rotation (Android 9+): a lineage
  previous key → release key, made once with `apksigner rotate`, given to
  `release.sh` by five optional variables (`HERBIER_SIGNING_LINEAGE`,
  `HERBIER_PREVIOUS_*`), which then re-signs the release with it; no
  rollback capability, so a debug-key APK can no longer replace it. The
  lineage is needed for that first release only: on the emulator (API 35),
  an APK signed by the new key alone updated the rotated install in place
  (same first install time), so later releases, CI's included, are signed
  by the release key alone and the five variables are unset again. `release.sh` always runs `apksigner verify` and
  prints the APK's versionCode, versionName and certificate digest, and
  fails when that versionName is not the bundle's (`app/version`): both run
  `git describe`.

## 5. Photo pipeline

```
capture / pick
  → read EXIF (date, GPS) with exifr, before any canvas work; the Android
    system photo picker empties the GPS tags of a picked copy (seen on the
    emulator, API 35)
  → decode with createImageBitmap (applies orientation)
  → preview: resize to ≤1600 px, encode JPEG q0.7 (or WebP), write to
    previews/<id>; insert Photo(pending) + outbox row
  → original (Drive target): write originals/<id>, insert its uploads row
  → queue pass (one at a time): lookup by appProperties, folders, then a
    Drive resumable session (POST uploadType=resumable, the metadata with
    parents and appProperties {herbier_photo_id, sha256}) into
    Herbier/<scientific or display name>/; its URL kept in the row
  → WorkManager job (Herbier's Uploader plugin; UNMETERED when « Envoyer
    seulement en Wi-Fi », else CONNECTED) PUTs the bytes to the session,
    resuming after an interruption; survives the app being swiped away
  → next pass, job succeeded: drive_file_id, upload_state=uploaded (one
    commit, outbox), delete the row and originals/<id>
  → on failure after 3 attempts: failed, badge « ↑ » stays, retry from
    Settings → « Envoyer maintenant »
```

- The queue (`photos/upload_queue.ml` decides, `photos_io/upload_queue.ml`
  runs; plan step 52): a pass reads the jobs (`Cap_uploader.jobs`), then each
  `uploads` row, oldest first, with its photo row. Passes are single-flight
  and run at startup, on resume, on sign-in, on coming back online, on every
  job change while the app runs, and interactively after a save that kept an
  original (the first Drive photo may show the consent). Only the install that
  holds an original uploads it: a photo pulled from another install has no
  row. A photo deleted, uploaded or switched to app-only discards its row,
  file and job.
- The job (`UploaderPlugin.java`, `UploadWorker.java`; the npm uploader
  `@capgo/capacitor-uploader` was replaced: a foreground service with no
  network constraint, no token hook and no response body): one unique
  WorkManager work per photo (REPLACE), exponential backoff from 30 s, at
  most 10 runs. Every run first asks the session what it holds
  (`Content-Range: bytes */N`) and sends the rest (a replacing job starts
  again at run 0). 200/201 → succeeded with Drive's file JSON; 404/410
  (session gone) → one attempt counted, the next pass starts a new session
  (a session that answers 404 at once must not start sessions forever);
  other final 4xx or 10 transient failures → one attempt of the queue's 3; a
  missing file is final at once. A failed job stays listed until a new job
  replaces it, so the queue saves the attempt only then (each pass counts
  that failure again from the same saved value). No foreground service,
  no notification: a photo fits WorkManager's 10-minute window and an
  interrupted run resumes. Its URL allow-list is Drive's upload endpoint
  (plus localhost in debug builds, for `scripts/upload-sink.mjs`).
- No token reaches the job: the session URL is the credential (Drive keeps a
  session a week; the queue starts a new one after 6 days), so a job waiting
  hours for Wi-Fi never needs a fresh token. A token or account-wide error
  (API disabled, scope, quota, 401 after renewal, rate limit, 5xx, network)
  while starting a session changes no photo: it ends the pass's starts and is
  kept as the row's last error. « Envoyer seulement en Wi-Fi » governs the
  bytes only: lookups and the session's start are a few hundred bytes on any
  network; changing it re-enqueues the waiting jobs, in the next pass.
- The session URL is kept in the `uploads` row, in the SQLite database that
  Android's backup includes (unlike the refresh token and the keep-alive KV):
  accepted. It can only write the bytes of one pending `drive.file` upload,
  for at most 6 days, and the backup sits in the Google account that owns the
  Drive.

- Drive token: `AuthorizationClient` with scope `drive.file`, requested
  lazily at the first photo to upload (handoff 4n: "Google Photos se
  connecte plus tard, à la première photo"). Tokens are 1-hour and cached by
  Play Services; only the queue's session starts need one (the job carries
  the session URL, no token).
  It is Herbier's own inline plugin (`GoogleAuthorizationPlugin.java`,
  `bindings/cap_google_authorization.ml`), not social-login's: that one takes
  scopes only at sign-in and has no silent "authorize this scope" call.
  `Auth.drive_token ~interactive`: an interactive call may show the consent
  screen (one at a time); a silent one fails with `Consent_needed` instead.
  Every token names the Drive account (below) with `setAccount`; with none
  chosen, no token is asked (`Drive_no_account`). Interactive calls are
  single-flight per email, so a consent for one account never answers a
  request for another. The plugin grants `drive.file` and nothing else. A
  401 from Drive → `clearToken` of that token (Play Services would hand it
  back otherwise), a new token, the same request once more.
- Drive account (M7.62): Drive has its own Google account, independent of
  the Supabase sign-in; signing in or out does not touch it. It is chosen in
  4m « Dossier Drive » through `GoogleAuthorizationPlugin.chooseAccount`:
  Credential Manager's « Sign in with Google »
  (`GetSignInWithGoogleOption` with the web client id), then
  `GoogleIdTokenCredential.getEmail()` (googleid ≥ 1.2.0). The id token is
  thrown away: never sent to Supabase, stored or logged. This is the
  documented way: an `AuthorizationResult` « does not contain any
  information about the user account that was used »
  (developer.android.com/identity/authorization, « Get user information
  during authorization »), which points to Credential Manager;
  `toGoogleSignInAccount()` is deprecated. Neither option builder has a
  login hint, so the session's email cannot be preselected: the chooser
  lists it with the device's other accounts. The email is the local setting
  `drive_account` (never synced; in Android's backup like the root folder
  ids, as it is not a credential: Play Services holds the grant). A build
  without a Google web client id has no Drive (`Unconfigured`). The sheet
  shows « Compte : <email> » with « Utiliser un autre compte », and the
  folder's name (M7.79, below). Another account is stored once its
  drive.file token is granted, in one transaction inside
  `Upload_queue.exclusive` (`Drive_root.store_account`); cancelling changes
  nothing. A new account forgets `drive_root_folder` (the old Drive's id)
  and keeps `drive_root_folder_name` (the user's choice, found or created in
  the new Drive at its first upload); the queue keeps its waiting rows, and a resumable session
  already started finishes in the Drive it began in (its URL is the
  credential). A new account also stores the time of the change
  (`drive_account_changed_at`, local): after a switch the health check's
  token is the new account's, and the old account's files answer 404, so a
  404 for a photo created before the change is no answer (a trashed or
  present answer still counts: the token reaches that file). A stopgap: such
  a photo deleted for good in Drive is not flagged; the clean fix is the
  account per photo (a schema change), left for later. An install that used
  Drive before this account existed kept the root folder id of the
  signed-in account its tokens named: at the next sign-in with no Drive
  account stored and the id set, the session's email is stored once as the
  Drive account (`Drive_root.seed`), so the folder is kept. A removed account or
  revoked consent shows the `No_account` / `Consent_needed` texts, which
  point to « Dossier Drive ».
- Choosing Drive storage (M7.72, M7.79): the first choice happens from 4m's
  « Google Drive » radio, not from the sheet. It runs the sheet's machine
  with `purpose = Turn_on` (`ui_model/drive_sheet.ml`, through the runner
  `ui/screens/settings/drive_flow.ml` the sheet also uses): the account
  chooser when no Drive account is stored, then an interactive drive.file
  token (consent asked while the user is choosing; when Drive refuses the
  stored account's token, e.g. the account was removed from the phone, the
  chooser opens once, since the sheet's « Utiliser un autre compte » is
  hidden under « Dans Herbier seulement »). A granted token writes the
  account and `storage_target = drive` in one transaction
  (`Settings.drive_choice ~storage`, `Drive_root.store_account`). No folder
  is chosen: the app's folder is found or created under the stored name at
  the first upload, or by a rename in the sheet. A cancel or an error
  (chooser, token, write) stores nothing; the radios read the stored value
  only, so they never left the previous one: "Drive without account" is not
  reachable from the UI. An install already in that state (an upgrade from
  before M7.72) keeps Drive checked and is not switched: « Dossier Drive »
  shows « Aucun compte choisi » and its prompt, and its sheet makes the
  first choice. A build without a web client id has the radio disabled with
  its reason; the Cloud project number gate of M7.72 is gone with the Picker
  (M7.79). Under the radio, once the storage is Drive with an account:
  « <folder name> · <email> ».
- Drive layout: the root folder's id is kept in the local setting
  `drive_root_folder`. Each session start that has a file to create (the
  lookup by `appProperties` found none) checks it
  (`files.get?fields=id,name,mimeType,trashed`, one request): a folder, not
  trashed, it is used wherever it was moved and whatever its name, and the
  name Drive gave is stored as `drive_root_folder_name` when it changed (a
  rename done in Drive's own UI shows in the sheet after the next upload);
  trashed, not a folder, 404 or 403 `appNotAuthorizedToFile` (the app is off
  its ACL, a lasting state), it is forgotten, then the stored name
  (« Herbier » by default) is found in My Drive's root (oldest wins,
  `trashed = false`) or created, and its id stored with that name, in one
  transaction (`Drive_root.apply`). With nothing stored, an app-made folder
  of that name already at the root (an earlier install) is adopted rather
  than duplicated. Any other error on the root folder (an unlisted 403, a
  malformed answer) is `Root_folder`, an `Account` error: the queue stops the
  pass and keeps every photo's attempts, the id is kept. A settings read that
  fails (not a blank value) sends nothing: the start waits for the next pass
  rather than create a second root. With `drive.file` the app sees only
  folders it created, so a user's own "Herbier" folder is never taken for its
  own. A different Google account answers 404 (or 403
  `appNotAuthorizedToFile`) for the old id, so the root is found again for
  the new account. The root is always the app's own folder (M7.79): 4m
  « Dossier Drive » shows its name in a field with « Renommer », which sends
  `files.update` (PATCH `files/<id>?fields=id,name,mimeType,trashed`, body
  `{"name": …}`; the app created the folder, so drive.file lets it rename
  it; a folder picked before the upgrade and kept by migration 6 is renamed
  through the grant the Picker gave, so « Renommer » then renames that
  user folder) with the account's interactive token, inside
  `Upload_queue.exclusive`, and stores the name Drive answers only on
  success (offline: nothing changes; a name Drive took but the settings
  write lost is reported « non enregistré », the next upload learns it).
  A blank name is refused before any request. With no id stored (another
  account in between, a reinstall) the app's folder is first looked up at
  My Drive's root under its current name and renamed, so no second root is
  made. A root gone (404, 403 `appNotAuthorizedToFile`, or answered
  trashed) or none found: a folder with the new name at My Drive's root is
  adopted, else created, and stored. To put the folder elsewhere the user
  moves it in Google Drive (the help line « Pour le ranger ailleurs,
  déplacez ce dossier dans Google Drive : Herbier le suit. »): the app
  follows it by id. Google Picker (M7.61/M7.62) was removed after the phone
  test of 2026-11-21: inside the WebView its frame asks to sign in to a
  Google web session the WebView does not have, and it cannot create a
  folder; a Custom Tab round-trip, an in-app folder browser (drive.file
  cannot list the user's folders; broader scopes are restricted) and SAF
  were rejected (docs/notes/google-picker-webview.md). A folder picked
  before the upgrade stays the root while it answers (local migration 6
  keeps its picked name), else it is forgotten as above. Species folders are still
  found or created by name inside the root (no species ids cached). The health check and « Ouvrir dans Google
  Drive » go by file id and are unaffected by moves. The species folder is the
  plant's scientific name, else its display name, else « À identifier »;
  files are not moved when the plant changes later. File names are
  `YYYY-MM-DD HH.MM.SS <last 8 hex digits of the photo id>.<ext>` in the
  device's zone (a v7 id's first digits are its timestamp, its last ones
  random). Before a session or `files.create`, a lookup by
  `appProperties.herbier_photo_id` makes the upload idempotent: an earlier
  upload whose answer was lost is found, not duplicated. The upload queue
  starts sessions (`start_session`, like `put_original`) one at a time per
  account: two first uploads of one species running together would create two
  folders; the byte uploads may run in parallel (they create no folder).
  Should Drive's search lag behind a create whose answer was lost, the next
  run uploads a second copy; pre-generated ids (`files.generateIds`) would
  close that window and are not used yet.
  `put_original` (the multipart frame) stays for #dev/drive and for a
  foreground fallback.
- Displaying an original (viewer, "Ouvrir dans Google Drive ↗"): open
  `https://drive.google.com/file/d/<drive_file_id>/view` (the form of the
  file's `webViewLink`, which is not stored: only `drive_file_id` is synced),
  as an external link Android hands to the Drive app; the app itself only
  ever renders the local preview.
- Health check (weekly, when online; `photos/health.ml` pure,
  `photos_io/health.ml` on the device): one `files.get?fields=id,trashed`
  per live `uploaded`/`original_missing` photo with a `drive_file_id`, one
  after the other with a silent token; `trashed` or 404 → `original_missing`,
  and back to `uploaded` when the file is present again (restored from the
  bin). An account-wide error (token, 401, API off, 5xx, network) stops the
  run and leaves it due; a file-only error skips that file. The changes found
  before a stop are committed, and the next run resumes after the last photo
  reached (the local setting `drive_health_cursor`, photos in id order), so a
  long list is covered over several runs. The date of the last complete round
  is the local setting `drive_health_checked_at`; the cursor is cleared then.
  Photos of a soft-deleted observation are checked too: their original is
  still the user's. Triggers (a Drive account chosen): start, resume,
  sign-in, back online, a Drive account or folder stored by 4m.
- 4m « Dernier envoi » is the local setting `last_upload_at`, written by the
  queue when an original reaches Drive on this install.
- Switching the storage to app-only while originals wait on this phone asks
  first; « Ne pas les envoyer » makes those photos app-only (a synced edit)
  and the queue discards their row, file and job; the setting is written only
  once that worked. « Les envoyer quand même » keeps them queued, and the
  Drive access prompt stays while they wait. Originals already in Drive stay
  there.
- App-only storage target (no Google): originals are simply not kept, only
  the preview, on the device alone (no Storage mirror).
- Google Photos: not implemented; the settings radio offers Drive and
  app-only, no Google Photos row.

## 6. Reference pipeline

Triggered when a plant gets a `gbif_key` (link intercepted, search pick,
"Lier", the choice of an identification, §12), on manual ↻, or on opening the
species page when online and the plant's rows are due (`refs/fanout.ml`): a
fetched source without a live row, a row older than 90 days, or a
`failed`/`partial` row older than one day (so one bad connection does not
leave the fiche empty for three months). The due check runs once per entry
into the fiche, never on the reloads the fetch itself causes.

```
gbif_key
  ├─ GBIF  species/{k}, /vernacularNames, /distributions (WCVP rows),
  │        occurrence/count, occurrence/search?datasetKey=<Pl@ntNet>&mediaType=StillImage
  ├─ Wikidata  list=search haswbstatement:P846={k} → wbgetentities
  │            → P5037/P961 POWO/IPNI, P3186 TaxRef, P3105 Tela, P3031 EPPO,
  │              P3151 iNat, sitelinks fr/en/de/it
  │  └─ Wikipedia REST page/summary/{fr sitelink title} (en sitelink when
  │     fr has none or answers 404): depends on the Wikidata entity
  └─ regional layer (if enabled):
       Tela  bdtfx/noms?masque={name} → nn, cd_nom
             bdtfx/taxons/{nn} (statut origine/introduction), baseflor
             (type_bio, floraison, écologie), coste (description), del images
       INPN  odata-inpn /taxa/{cd_nom}, /protections/articles/entries,
             /redLists/entries
```

- The fetch is three concurrent branches (`refs/fanout.ml`, sans-IO programs
  of GETs run by `refs_io/http.ml`'s `run`): gbif (species, then vernacular
  names, distributions, occurrence count), plantnet (media), and wikidata →
  wikipedia. Each branch's rows are written in one save when that branch
  ends, so a slow or failing branch neither delays nor rolls back another,
  and 4f fills progressively.
- Statuses: `missing` = the source answered it has nothing (GBIF species 404,
  no Wikidata item, no Pl@ntNet image, no sitelink or summary 404);
  `failed` = no call of the row gave a decodable answer; `partial` = some
  did; `complete` = all did. Keep rule (`Fanout.decide`): a `failed` row is
  never written over a live stored row (a timeout must not blank data that
  was right; it is written only when nothing was stored, so the due rule
  retries it); a `partial` row keeps the stored members of its failed parts.
  When the Wikidata entity could not be read (Wikidata `failed`, or
  `partial` with only the search), Wikipedia counts as `failed`: a stored
  row stays, and without one a `failed` row is written, so the one-day
  retry applies to it too.
- Relinking a plant to another taxon soft-deletes the live reference row of
  every fetched source in the link's transaction (whatever is live when it
  commits, so a branch of the old key that saved just before is retired
  too), and supersedes any fetch still running for the old key (its branch
  saves not yet made are dropped): the keep rule would otherwise keep the old
  taxon's rows under the new key. The plant's non-GBIF `plant_refs` (links
  pasted in 5a « Liens de référence ») are soft-deleted in the same
  transaction: they named the old taxon, and 4f falls back to the links
  derived from the new one.
- The fetch starts only online, like ↻; offline, a just-linked plant is due
  and the next opening of its fiche fetches it.
- Each source writes its own `reference` row (source, payload, status), so a
  failing source never blanks the others and every row in the UI cites its
  source (handoff 4f: "Une ligne sans donnée disparaît. Toute donnée cite sa
  source."). The payload (`refs/payload.ml`) is an object with one member per
  call, holding that call's body as returned, pruned to the fields the
  decoders read (≈ 100 KB per plant instead of ≈ 700 KB), so the decoders
  read stored payloads unchanged: `gbif` {species, vernacular_names,
  distributions, occurrence_count}, `plantnet` {media} (the Pl@ntNet dataset's
  occurrences, fetched from GBIF but cited as Pl@ntNet, hence its own row),
  `wikidata` {search, entity}, `wikipedia` {summary}. A failed call's member
  is absent.
- The species page reads a **projection** of the reference rows into the
  handoff's `ReferenceSnapshot` fields (vernacular per language, family, life
  form, native/introduced range, FR status, protection, red list, flowering
  months, habitat/ecology chips, toxicity, organ photos, links). Altitude is
  dropped; height is parsed from Coste text when present. The projection
  (`refs/projection/`) reads whatever parts a row holds, whatever its
  status, and a part that fails to decode degrades its fields only. Rules:
  vernacular names from GBIF rows and Wikidata P1843 in fr, en, de, it, top
  three by votes (case-insensitive); native/introduced ranges from the WCVP
  rows of GBIF distributions; red list from the global IUCN row only
  (national lists are the regional layer); toxicity is the first sentence of
  the Wikipedia summary naming toxicity; organ photos one per organ; links are
  the plant's `plant_refs` URLs when they are https and point at their source
  (else ignored), else URLs derived from the GBIF key, the
  summary page and the Wikidata ids (POWO, INPN, Tela, iNat, EPPO).
- Organ photos: four thumbnails (fleur/feuille/fruit/port) picked from the
  GBIF Pl@ntNet dataset media by `title` suffix, downloaded to `refthumbs/`
  with licence and attribution kept for display. `ref_images` is a cache of
  the live Pl@ntNet reference row (`refs_io/organ_thumbs.ml`, rules in
  `refs/organ_photos.ml`): after each fetch and on each fiche entry, while
  online, the rows follow the projection's organ photos (only
  `https://bs.plantnet.org/` URLs), then the missing thumbnails are
  downloaded one at a time per plant; a failed one is tried again on the next
  sync. The image host sends no CORS headers, so the bytes come through
  Capacitor's core `CapacitorHttp` plugin (`bindings/cap_http.ml`, base64
  body, redirects not followed; the global fetch patch stays off), and are
  resized on a canvas. 4f shows a tile only when its row's URL is
  the projection's and its thumbnail exists, so a relink never shows the old
  taxon's photos.
- Distribution map on the species page: GBIF density tiles
  `v2/map/occurrence/density/{z}/{x}/{y}@1x.png?taxonKey=` over the base
  map; attribution GBIF.
- Wikimedia requests carry `Api-User-Agent: Herbier/<version> (<contact>)`;
  Wikimedia without it is limited to 10 req/min. The WebView drops a
  page-set `User-Agent`, so the other sources see the WebView's own, and they
  get no custom header: GBIF refuses CORS preflights.
- Reference fetches go through a small **rate-limited queue** (at most one
  request in flight per source, ≤3 overall) since we call several public
  APIs at once. Organ thumbnail downloads do not: they go through
  `CapacitorHttp`, one at a time per plant (two fiches opened in a row can
  download at once).

## 7. Link interception and resolution

Manifest `intent-filter`s (`VIEW` + `BROWSABLE`, `https`) for Pl@ntNet's
hosts only (user decision 2026-11-12): `identify.plantnet.org` and the
Pl@ntUse hosts below. The resolver classifies all the hosts below and also a
`www.` variant of each, the non-Pl@ntNet ones only when pasted in « Liens de
référence » (5a) or shared as text; gbif.org may be re-added to the manifest
if needed:
`www.gbif.org`, `gbif.org` and `m.gbif.org`: `/species/*` and
`/{lang}/species/*`;
`identify.plantnet.org`: `/{project}/species/*` and
`/{lang}/{project}/species/*`, the same two depths for `observations`;
`plantuse.plantnet.org`, `uses.plantnet.org` and the old
`uses.plantnet-project.org`: `/{lang}/{page}` and deeper (the Pl@ntUse wiki,
linked from Pl@ntNet species pages; `plantuse.plantnet.org` is current, the
old host redirects there and `uses.plantnet.org` no longer resolves, checked
2026-11-12; old links still classify; a page the classifier rejects lands on
4i with an empty query);
`*.wikipedia.org` (and `*.m.wikipedia.org`): `/wiki/*`;
`powo.science.kew.org`: `/taxon/*`;
`inpn.mnhn.fr`: `/espece/cd_nom/*` and `/explorer/especes/*`;
`www.tela-botanica.org` and `tela-botanica.org`: `/bdtfx-nn-*`;
`www.inaturalist.org`, `inaturalist.org` and `m.inaturalist.org`: `/taxa/*`.
A manifest `pathPattern` is Android's simple glob, whose `.*` stops at the
first occurrence of the next character and never backtracks: `/.*/species/.*`
matches one segment before `species` only, so each depth is its own pattern.
Plus `SEND text/plain` via the share-target plugin (Pl@ntNet's share). On
Android 12+ the user enables the Pl@ntNet hosts once under "Ouvrir par
défaut" (no Digital Asset Links since we
do not own these domains); the share sheet path needs nothing. Both paths
ship in v1. A link or share that cold-starts the app is not lost: Capacitor
runs the launch intent through the plugins' `handleOnNewIntent`, and both
`appUrlOpen` and `shareReceived` are retained until the first listener
registers (`ui/intake.ml`, after the router starts). An activity recreated
after process death or relaunched from recents still carries its first
intent; `MainActivity` drops it, so that link does not open 4j again.
Android back from an outside 4j, or from the fiche it opened, returns to the
app the link came from when Herbier had no user gesture before the link
(cold start, or a warm app untouched since its last navigation): Chromium's
history-manipulation intervention marks the entry under `#lien/` skippable,
so the `backButton` event's `canGoBack` is false and the router exits. This
is accepted as expected Android behaviour (user decision 2026-11-12); it
matches what ✕ does, and the in-app ← still goes to Collection.

Resolver (OCaml, shared by screens 4i/4j/4k/5c):

```
input (URL or text)
  → classify by host/pattern
     gbif       → key from path
     plantnet   → decode "Genus species Author" from path → GBIF species/match
     plantnet observation → no name in the path, and Pl@ntNet's API has no public
                  route for an observation (`/v2/observations/{id}` is for partners;
                  identification, §12, takes photos, not ids):
                  4i fallback with the shared text around the link (often empty)
     plantuse   → "Genus_species" wiki page name → GBIF species/match
     wikipedia  → REST summary → wikibase_item → Wikidata P846
     inpn/tela  → Wikidata by P3186/P3105 → P846 (not the regional APIs; gaps → 4i;
                  INPN/Tela as sources are the M4.59 regional layer)
     powo/inat  → Wikidata by P5037/P3151 → P846
     free text  → GBIF species/suggest + search?qField=VERNACULAR
  → gbif_key + immediate partial snapshot (canonical name, family)
     = Resolve.Taxon (the GBIF taxon), Candidates (free text), or
       Unresolved {query, why} with the text 4i is prefilled with
     a synonym is replaced by its accepted taxon (one hop); a name match
     at a rank above species is no species; an explicit GBIF key is
     honoured at any rank; a Wikipedia disambiguation page is no species
  → screen 4j pre-filled; full reference fetch in background after save
```

What the Pl@ntNet app actually puts in a share (URL vs text) is unverified;
the classifier must accept both a bare URL and text containing one.

## 8. Map

- MapLibre GL JS behind a JS facade (`map.js`, ~100 lines) exposing: create,
  set style (for the offline/online switch below), set GeoJSON source, on
  click/movestart/moveend/idle/error (movestart reports whether a gesture
  started the move: 5b disables « Valider » while the camera moves, and only a
  user move cancels the late fly to the entry fix), getCenter, getZoom, flyTo,
  fit bounds (capped at a maximum zoom), rendered ids, resize, remove. Bound from OCaml with Brr `Jv`;
  styles and GeoJSON
  cross as JSON text. Herbier's sources and layers are merged into the style
  JSON in OCaml (`Geo.Style.with_overlays`), so they survive `setStyle`.
- MapLibre 6 is bundled by esbuild into the IIFE `vendor.js`; its worker is
  served as the file `maplibre-gl-worker.js` and set with `setWorkerUrl`.
- Sources: the 500 m semantics come from a **pre-clustering step in OCaml**
  (`Places.cluster`): below zoom 15 the map shows one point per place, in a
  GeoJSON source with `cluster: true` whose MapLibre clustering only merges
  places that overlap on screen; from zoom 15 it shows the observations
  themselves (4b, `Geo.Style.detail_zoom`).
- Styles: OpenFreeMap `positron` online; offline, the same style with the
  tile source swapped to `pmtiles://` pointing at `tiles/<region>.pmtiles`
  (Protomaps `@protomaps/basemaps` flavour `white`). Switch is automatic on
  connectivity change.
- GPS accuracy: a metric circle, never a number in the UI (handoff 4h): a
  GeoJSON polygon computed in OCaml (`Geo.Features.circle`, 64 vertices on
  the sphere of `Places.distance_m`) in a source drawn by a fill and a line
  layer, exact at every zoom and latitude.
- Mini-map (observation screen): a non-interactive MapLibre instance framing
  the accuracy circle (`Widgets.Mini_map`); tapping it opens 5b, the move-point
  screen (`Route.Move_point`), since M8.76 by the user's decision (it opened
  4b centred, through a one-shot framing in `State.map_view`, which 4c's « ◎ »
  still uses).
- Moving a point (5b): an interactive map under a fixed DOM pin whose foot
  is the map's centre (the map is laid out above the drawer); the stored
  position is a grey ghost layer (`Geo.Style.origin_layer`). « Chercher un
  lieu » is a Photon search on submit, biased to the centre, run only when
  « Photon en ligne » is on in 4m (M5.57; otherwise a line says so and no
  request leaves); title and
  « déplacé de N m » follow the camera on `moveend`; a picked result's name
  only titles the drawer, it is never stored. « Valider » (disabled while the
  camera moves, so it saves what the drawer shows) writes the
  centre at the last `moveend` (6 decimals, longitude wrapped into [-180, 180), latitude clamped)
  with `accuracy_m` and `place_derived` cleared, `place_label` kept only
  within 500 m of the old point, through `Observations.upsert`; `App.save`
  then runs the reverse geocoding below for the new point (`Move_plan`).
- Place names for `place_derived` (M5.57: positions stay on the phone
  unless the user turns a source on). `Geo.Place_name.resolve` (pure) names
  a point, in order:
  1. the user's own places: the nearest live observation with a non-blank
     `place_label` within 500 m (`Observations.labelled`), with no network;
     its trimmed label is stored verbatim (no « Près de »). The nearest
     labelled observation, not the majority name of the place 4b groups it
     into: it may differ from that name when two named places lie within
     500 m, and clusters change as observations are added while the stored
     name does not. The copy is a snapshot: renaming, clearing, deleting or
     moving the labelled place does not update it, and a source turned on
     later does not replace it (the row is no longer unnamed); giving the
     observation its own label overrides it. A labelled observation is not
     named at all (`Observations.to_geocode` leaves it out: its label is its
     name), so it never reaches a remote source; clearing its label makes it
     pending again;
  2. each place-name source the user turned on in 4m « Noms de lieux », in
     order « IGN hors-ligne » (the downloaded commune packs,
     `Geo.Communes.name`, no request, online or not), « IGN en ligne »
     (Géoplateforme, `Geo.Geocode.reverse_ign`) then « Photon en ligne »
     (`Geo.Geocode.reverse_photon`). All are **off by default** (local
     `settings` keys `place_source_ign_offline`, `place_source_ign_online`,
     `place_source_photon_online`; unset or unreadable = off), mirrored in
     `State.place_sources`. With both IGN switches on, a point in a
     downloaded département gets its commune, never the online lieu-dit;
  3. else nothing is stored, and 4c, 4b's sheet and 4h print
     « Lieu inconnu » (`Places.unknown_name`, never stored: a stored
     placeholder would sync as a fake name and stop later sources).

  With a source on but the phone offline the outcome is `Deferred`: no
  request, asked again on the `online` event. Rules of the sources:
  - IGN: inside a coarse box of metropolitan France and Corsica, the nearest
    Géoplateforme lieu-dit (habité or not) within 500 m, else the commune
    containing the point; outside the box, no request. Photon's name counts
    only when it is an OSM `place` (city … islet), else its district, else
    its city. With both on, the chain is M5.43's (IGN, then Photon);
  - the row stores the phrase « Près de … » with the French contraction
    (du, des, de la, de l’, d’), which 4c and 4h print as is;
  - written by a conditional `Observations.set_place_derived` (live, same
    position, still unnamed) through `App` with its outbox entry, so a late
    answer never overwrites a move or a newer name;
  - `App.geocode_pending` runs online or offline (own places need no
    network): at startup, when the window comes back online (main.ml's
    `online`/`offline` listener keeps `State.network` current), after every
    `App.save` that changed rows, and when a 4m switch is turned on; newest
    observation first, one at a time;
  - a remote miss, or a payload or HTTP error, is not asked again in the same
    session (the own-place lookup still runs); the next app start, or
    turning an online source on (once its setting is saved, which clears that
    list; turning « IGN hors-ligne » on keeps it), asks again. A switch whose write fails falls back to the stored value,
    except an opt-out, which stays off for the session; 4m says so. A
    transient error (network, timeout, 429, 5xx) stops the run and leaves
    the observation to the next trigger;
  - one request in flight, at least 1 s between two starts to the same
    provider, coordinates sent with 5 decimals (about 1 m, no coarser than a
    phone fix), names over 200 bytes dropped. `Geo.Geocoder` reads no
    setting: callers gate, and pass an `allow` predicate (`Place_name.allows`
    of the current switches, 5b's `can_search`) asked again when a request
    leaves the queue, so a source turned off while a request waits sends
    nothing (one already sent cannot be withdrawn). It logs every request it
    starts, on the console as `geocode: GET <provider> <endpoint>` (no query
    string: no coordinates or search text in logcat) and, in dev builds only,
    in the list behind the dev hook `herbierDev.geocodeRequests()` (whole
    URLs), so "no request left the phone" is checkable;
  - « IGN hors-ligne » (M5.58): 4m « Ajouter un département » fetches the
    list of départements from the Géoplateforme WFS (layer
    `ADMINEXPRESS-COG-CARTO.LATEST:departement`), then a tap downloads that
    département's communes (`…:commune`, `CQL_FILTER` on the département
    code, which only a valid code shape reaches; one page of at most 5000,
    a truncated answer refused) through `Geo.Geocoder` (logged like every
    request; it sends a département code, no position, so no switch gates
    it). The download holds the geocoder's one in-flight slot for its whole
    transfer (at most 120 s): reverses and 5b searches wait behind it. The
    phone simplifies each ring (Douglas–Peucker, 20 m) and stores the pack
    (§3); a successful download turns the switch on. Packs load into memory
    at startup; a geocode run and a download wait for that load. The lookup
    is point-in-polygon (even–odd, holes excluded), else the commune whose
    boundary is nearest within 50 m (slivers between independently
    simplified neighbours, and a point just outside a downloaded
    département's outer edge, which simplification also moves: a point truly
    inside can land there, so the fallback crosses that edge, into a
    département not downloaded or abroad, by up to 50 m), else the next
    source. A point already tried
    remotely this session still gets the pack lookup. Data: IGN Admin
    Express COG carto, Licence Ouverte 2.0, credited in 4m;
    « Toute la France » (M5.73) downloads every département of that list
    (overseas included: the WFS serves 971–974 and 976 with the same
    request; the 4m panel says so) through the very same per-département
    path, one after another in the list's code order, skipping those
    already present (a pack whose file did not load is downloaded again):
    resuming is just running it again, no run state is stored. The plan and
    the run are pure (`Geo.France_packs`, a functor over the IO, tested
    with a fake download). Failures: a transient one (network, timeout,
    429, 5xx, a body that is not JSON at all: the Géoplateforme answered 3
    of 101 requests with a 200 and a metrics page while measuring) is
    retried after 5, 20 then 60 s, then the run stops (only this run
    retries a non-JSON body: elsewhere the user or the next trigger asks
    again); a bad answer for one département skips it (listed at the
    end); 401 or 403 (the service refuses this client), offline, a file or
    a store error stops the run. One request at a time with the
    geocoder's spacing, no extra pause. A cancel takes effect between
    départements or during a wait; the one in flight finishes and is kept.
    The run stays in the WebView; while it goes, a foreground service of
    type dataSync (`ForegroundRunPlugin`, `ForegroundRunService`, M5.78)
    keeps the process at foreground priority with one ongoing
    notification, « IGN hors-ligne : n / total départements » and
    « Interrompre » (the in-app cancel), started after the plan is
    recomputed (none when nothing is left), updated at each report,
    stopped at every outcome, at the next app start and when the task is
    removed; the notification permission is asked at the run's start on
    Android 13+ and a refusal only hides the notification. A stop that
    comes before the service went foreground is deferred: the service goes
    foreground, then stops itself (Android crashes an app whose
    `startForegroundService` is not followed by `startForeground`); the
    notification is posted only while the service is foreground, so none
    outlives it. Without the
    service Android cuts a background app's network within seconds.
    Capacitor does not pause the WebView's timers in the background
    (`KeepRunning` default); the spike's measurements are in
    `docs/notes/webview-background.md`. On Android 15+ the dataSync
    budget's timeout cancels the run like « Interrompre ». A single
    département stays a foreground download. The estimate is
    the sum of a measured per-département size table (`Geo.France_sizes`)
    over what is left; on mobile data (`@capacitor/network`) a large
    transfer (the table's gzip column, ≥ 10 Mo) shows a warning, never a
    block. « Supprimer tout » deletes every pack; while it or a run goes,
    no other download, delete or run starts;
  - a one-time dialog at first opening (`Ui.Location_notice`, flag
    `location_notice_seen`) says positions stay on the phone, lists each
    source with what it sends to whom, and that the map's background tiles
    come from OpenFreeMap for the area shown.

## 9. Repository layout (sketch; `layout.md` is the decided version)

```
herbier/
  dune-project    two packages: herbier (the app), postgrest (lib/)
  lib/
    postgrest/    generic sans-IO PostgREST client: typed columns, row decoders, request rendering
  app/            OCaml sources (js_of_ocaml)
    ui/           rb.ml (react↔Brr glue), screens, theme.ml (reads CSS custom properties)
    store/        hand-written SQL over the sqlite plugin, schema migrations, outbox, tables.ml (generated columns)
    sync/         Postgrest → Brr fetch adapter, pull/push
    photos/       exif, compress, drive client, upload queue
    reference/    per-source clients, projection, rate limiter
    resolver/     link/text → gbif_key
    map/          maplibre facade bindings
    capacitor/    plugin bindings (Jv)
  web/            static shell: index.html, sass, fonts, map.js; Capacitor webDir → _build/default/web/dist
  android/        Capacitor project (generated), manifest intent-filters
  supabase/       hand-written migrations, schema dump, RLS, RPC functions, config
  docs/
```

## 10. Spikes before committing to the stack

Each is one or two days and answers a question the reports left open.

1. **Shell spike**: jsoo + Brr "hello" in Capacitor 8; share-target receives
   a Pl@ntNet URL; a `VIEW` filter on `gbif.org` opens the app after
   enabling it in "Ouvrir par défaut"; a WorkManager upload (Herbier's
   `Uploader` plugin, M7.52) completes with the app swiped away, on Wi-Fi only. Pass = Capacitor
   stays; fail = same OCaml in a TWA.
2. **Storage spike**: `@capacitor-community/sqlite` from OCaml, FTS5 search,
   a 300 KB preview written to `Directory.Data` and read back as a blob URL.
3. **Map spike**: MapLibre in the WebView with OpenFreeMap positron. The
   second half (a PMTiles file read from the filesystem through the
   `pmtiles` protocol, offline) is deferred with the offline region to v2;
   if filesystem-backed PMTiles then fails, fall back to an `addProtocol`
   write-through cache of visited tiles.
4. **Auth spike**: Credential Manager sign-in → Supabase `signInWithIdToken`;
   `AuthorizationClient` for `drive.file`; confirm the OAuth client can be
   "In production" with no verification prompt.
5. **Reference spike**: run the §6 pipeline for two species from OCaml and
   render the projection; measure how many fields come back empty.
6. **UI spike**: write the `rb.ml` glue (react + ReactiveData over Brr),
   then screen 4a (Collection: tag chips, search, grid) over rows from the
   local store (spike 2 comes first) and the bottom sheet
   drag as a signal-bound transform. Check that leaving and re-entering the
   screen releases every binding (no stale updates, no growth in
   `performance.memory`). If it disappoints, redo 4a in ocaml-vdom and
   compare.
7. **Identification spike** (added 2026-11-16 with §12, plan M9.63): a
   Pl@ntNet key exposed for `https://localhost` used from the WebView with
   `fetch`; the identify answers recorded as fixtures; how many related
   images a species gets; a preview's scores against a q0.9 encode of the
   same original. Pass = a key the user exposes for `https://localhost`
   and types in 4m works from the WebView (§12, decided 2026-11-16); fail =
   plan R10 (a native request with a key that is not exposed).

## 11. Non-goals restated

No identification model on the device (identifying is in scope since
2026-11-16 and goes through Pl@ntNet's API, §12). No sharing and no account
management: several separate accounts can sign in to the same project, each
seeing only its own rows (owner-only RLS on every synced table), but nothing
is shared between them and the app has no invitations, roles or user list.
No Google Photos (for now), no server-side rendering, no push
notifications, no Play Store listing required (sideload is fine; Play's
target SDK rules do not apply).

## 12. Identification (Pl@ntNet identify API)

Added to the scope on 2026-11-16 (plan M9; Claude Design tour 6 in
`design_handoff_herbier/identification/`, screens 6a–6k). Identifying is one
more way to name a plant, next to the name field, a link and a search: the
photos go to Pl@ntNet, the proposals come back, and choosing one links the GBIF
taxon Pl@ntNet gives, after which the reference loads as after an intercepted
link (4j, §6). Facts, quotes and sources:
`exploratory_research/plantnet-identify-api.md` (2026-11-16).

```
photos of one plant: previews, at most 5 (4d in memory; 4k, 4g previews/<id>.jpg)
  → POST https://my-api.plantnet.org/v2/identify/<flora>
         ?lang=fr&include-related-images=true&nb-results=5[&no-reject=true]&api-key=…
         multipart/form-data: images (JPEG), organs (auto, or the one the user set)
  → 200  proposals in Pl@ntNet's order: score, names, family, gbif.id, related
         images; predictedOrgans; remainingIdentificationRequests
    404  "Species not found": not a plant (6g; « Voir quand même » re-asks with
         no-reject, which may still answer 404)
    429  the day's 500 are used up until 00:00 UTC · 401 the key is refused
    403  "CORS error: Origin not allowed": the key is not exposed for the app
         (on screen as unreachable, « Réessayer »; the console line names it)
    timeout, network, 5xx, 400/413/415, malformed: « Pl@ntNet n'a pas répondu »
         (« Réessayer »)
  → a choice: Refs.Resolve.resolve (Gbif id), or the name match without an id,
    as for a link (§7: the one-hop synonym rule)
  → 4h (M8.76; 4d's save target until M8.75): attach or create, as 4k
    · 4k: attach or create · 4g: link, free name → alias
  → the reference fetch (§6), as after an intercepted link
```

- **Entry points.** 4d Noter: the Identifier button in the name field (6a);
  with « Identifier dès la photo » (on by default, 4m), the session's first
  photo, shutter or gallery, opens the send screen (6b) at once. Later, online:
  « Identifier avec Pl@ntNet » on an « À identifier » observation (4k → 6i,
  6j) and « Identifier » on a free-name fiche (4g → 6k), which sends one
  observation's photos (Pl@ntNet assumes one individual per request).
  *Superseded 2026-11-19 by the user's feedback (M8.75, M8.76):* Noter has no
  Identifier button and its first photo opens nothing; identification of a new
  observation is from its screen 4h (M8.76), with « Lier » / « + Créer » as
  in 6j, and « Identifier dès la photo » opens the layer there right after
  Enregistrer (4d decides it at its first write: no name typed, the setting
  on, a key, online; 4h checks the gate again before opening, so a network
  lost meanwhile sends nothing and leaves the button). 4h's button shows while
  the observation is « À identifier ». The 4d (6e) bullet, 6b's return to Noter (Screens) and « the
  first photo » (Offline) below describe the former Noter entry.
- **The request.** `POST /v2/identify/{flora}` with the key as the `api-key`
  query parameter, `lang=fr` (French common names), `include-related-images=true`
  (the closest images of each species), `nb-results=5` (the design lists three
  to five; fewer results answer faster) and `no-reject=true` only for « Voir
  quand même ». The body is `multipart/form-data`: one `images` part per photo,
  at most five, named `photo-<i>.jpg` (never the gallery file name, which
  Pl@ntNet echoes in `predictedOrgans`), each with its `organs` value: `auto` unless the user corrected
  the detected organ (« fleur ▾ ») or added a photo of an organ (« + feuille »).
  Built with Brr's `Form.Data` (the WebView sets the boundary) through
  `Timed_fetch.request_form`, 30 s, one request at a time per caller (a newer
  one makes the older answer stale), never retried by itself.
- **Where the code lives.** `app/identify/` is pure and native: it defines
  a `TRANSPORT` signature (an abstract `'a io`, an abstract preview `image`,
  `post_form` returning status and body text or a timeout / network
  failure, and `get` for the flora list) and the functor
  `Identify.Make (T : TRANSPORT)`, which builds the request (flora, organs,
  `include-related-images`, `no-reject`, `lang=fr`, the key as `api-key`),
  decodes the answer, classifies the errors and applies the rules below; its
  tests run it over a fake transport replaying the recorded answers. There is
  no `identify_io` library: the Brr transport (`Form.Data` with the preview
  Blobs, the 30 s timed fetch, error mapping without the URL) is one module,
  `ui/app/plantnet_transport.ml`, and `ui/app/identification.ml` applies
  `module Identify_io = Identify.Make (Plantnet_transport)` and keeps the
  key (Preferences), the per-caller staleness and the session's flora list,
  as `sync/` applies `Rest.Make` over its own transport (layout §2). It also
  reads the stored previews (through `store_io/files.ml`) before a request,
  so an unreadable one is its own error, never a network failure.
- **What leaves the phone.** The device previews (≤ 1600 px, JPEG q0.7,
  re-encoded on a canvas, so without EXIF) and the flora's id: no position
  (the identify route takes none, and the flora list is asked without
  `lat`/`lon`), never an original. Pl@ntNet's terms: the photos "are not stored
  in the database", they stay "in our server volatile memory during the
  identification process"; the query history (date, time) is kept; hosted by
  CIRAD in Montpellier. If previews identify worse than a q0.9 encode (plan
  R13), 4d sends a q0.9 encode made at capture, still from a canvas.
- **CORS.** The API answers preflights and errors with the caller's origin
  (`https://localhost` for the WebView, observed 2026-11-16), so `fetch` works
  and reads error bodies. A key used from a browser must be **exposed** in the
  Pl@ntNet account, and is then accepted only from its "Authorized domains"
  (checked on `Origin`) and, for requests without `Origin`, only from its
  "Authorized IPs". A key that is not exposed is refused from every `Origin`,
  `https://localhost` included (403 `{"message":"CORS error: Origin not
  allowed"}`, readable by the WebView), and answers 200 without one (spike,
  `notes/plantnet-webview.md`); once exposed with `https://localhost` among
  its "Authorized domains", it answers 200 to that origin (curl and the
  WebView itself), 403 to any other and 403 « remote IP not allowed »
  without one (plan R10 closed). The quota headers are not exposed to CORS:
  the WebView reads `remainingIdentificationRequests` from the body.
- **The key never reaches a log.** It rides in the query string, so the
  console line is `identify: POST <flora> <n> photo(s) → <status>, <remaining>
  left today`, never the URL; the fixtures are recorded with the key stripped.
  A non-2xx's line names its error class (`→ 403, key not exposed for the
  app`), never the body.
- **A key not exposed is a generic error to the user** (Tristan,
  2026-11-16: « juste une erreur générique », with a hidden log for that
  case, never the CORS cause on screen). The 403 « CORS error: Origin not
  allowed » keeps its own class (`Key_not_exposed`) for the console line;
  6g shows it as it shows an unreachable Pl@ntNet, « Pl@ntNet n'a pas
  répondu » with « Réessayer » (Tristan, 2026-11-16: the key may be exposed
  meanwhile, and the user never sees the cause); so do a refused request and
  a malformed answer. Each « Réessayer » is a tap and a credit. The setup
  help in 4m's key row (66) still asks for the key to be exposed.
  4m's flora list keeps « Réessayer » under every error, the generic one
  included: the list costs no credit, and the key may have been exposed
  meanwhile.
- **The answer, fields used.** Per proposal: `score` (0 to 1, shown as a
  percent), `species.scientificNameWithoutAuthor` and
  `scientificNameAuthorship` (the Latin line), `species.commonNames` (French
  with `lang=fr`; the first one names a new fiche), `species.family`, `gbif.id`
  (a string in every recorded answer, a number in the OpenAPI: both decode; it
  may be missing), and `images` (organ, author, licence, citation, `url.s` for
  6c's tiles, `url.m` for 6d), kept only under `https://bs.plantnet.org/`.
  `predictedOrgans` gives each photo's detected organ, `preferedReferential`
  the flora `all` picked, `remainingIdentificationRequests` the day's credits
  left (logged). The rest (`bestMatch`, `powo`, `iucn`, `version`) is ignored.
- **Rules** (pure, `app/identify/`, tested on recorded answers): the
  proposals keep Pl@ntNet's order; each shows its four closest images, the rest
  as « +N »; 6d orders a species' images by my photos' organs (in photo order,
  then the rest) and shows on top my photo of the shown image's organ (else my
  first photo). Uncertain (6f): the best score below 0.5, or less than 0.15
  ahead of the second (two constants, to tune). The organ to add: a flower when none was sent, else a
  leaf, else any (« + photo »), none at five photos. « Dans ma collection »: a
  live plant whose `gbif_key` is the proposal's id (`Ref_pick`'s matching),
  with the count of its live observations. 6c matches on that id alone (no
  GBIF resolution exists yet); 6e's owner also matches the resolved and
  accepted keys once GBIF has answered (`Owned.has_key`, one rule for both).
- **The choice and the GBIF id.** Pl@ntNet's `gbif.id` is a GBIF backbone
  `usageKey` (the documentation's ids are accepted backbone species, checked
  2026-11-16), Herbier's primary key (`stack.md`). Choosing resolves it with
  `Refs.Resolve.resolve (Gbif id)` (a synonym becomes its accepted taxon), or
  with the name match (`Plantnet "<Latin name and author>"`) when Pl@ntNet gave
  no id, and with the name match too when GBIF does not know the id (R12):
  one program (`ui_model/identify/choice.ml`) run by `App.resolve_choice`
  through `refs_io`'s queue, as an intercepted link is resolved.
  - 4d (6e; superseded 2026-11-19, M8.75): the field shows my display name when the taxon is already a
    plant of mine, else Pl@ntNet's first French name, else the Latin name.
    « Enregistrer » never waits: a plant of mine gets the observation (no
    duplicate); otherwise `App.create_linked` creates the plant with the
    resolved taxon, or with Pl@ntNet's own id and names when GBIF has not
    answered yet (plan R12). A proposal without id, or whose id GBIF does not
    know and whose name matches no species (a genus-level « Hibiscus spp. »),
    saves as a free name (Pl@ntNet's first French name), or, as a typed name
    would, to a plant of mine with that name or alias. Known window: a save
    made before GBIF answers only knows Pl@ntNet's id, so a synonym id with
    the species already mine under its accepted key makes a second plant
    (Pl@ntNet's ids are accepted species, so this needs data drift; merging
    the two is by hand). The answer kept for a
    reopen is a 200 or a 404 (the same photos would get the same « no plant »
    and spend a credit); any other error, the key not exposed included, is
    asked again at the next tap, since it may pass by then.
  - 4k (6j): « Lier » attaches the observation to the plant of mine;
    « + Créer » creates the linked plant with the observation's upsert, as
    4k's « + »; then the next observation of the queue. The choice is
    resolved through GBIF first, so « Lier » / « + Créer » is decided again on
    GBIF's key and accepted key. GBIF unavailable: linked with Pl@ntNet's own
    taxon (R12); GBIF knows no species: a free-name plant of Pl@ntNet's name,
    or my plant of that name or alias, as in 4d. « + <organe> » saves the
    picked photo on the observation (4h's « + », gallery) and re-asks;
    « Aucune ne correspond » and ← return to 6i, no answer kept. A key not
    exposed is 6g's generic « Pl@ntNet n'a pas répondu »: 6i and 6j add no
    text about it.
  - 4g (6k): « Identifier » sends the newest observation with photos (its
    first five previews, 4h's order); « + <organe> » saves the picked photo
    on that observation. 6c and 6d say « Aussi dans ma collection : <nom> »
    when another plant has the taxon (two plants may share one), and every
    proposal's action is « Lier ». The choice is resolved through GBIF, then
    `App.link ~name` (`Ref_pick`'s `Relink`): Pl@ntNet's first French name
    becomes the display name and the free name an alias, as 4g's « Lier ».
    GBIF unavailable: linked with Pl@ntNet's own taxon (R12); GBIF knows no
    species, or is unavailable for a proposal without id: nothing written, a
    line under the hero says why (the plant keeps its free name). A key not
    exposed is 6g's generic « Pl@ntNet n'a pas répondu »: 6k adds no text
    about it.

  Then the reference fetch of §6 runs, as after a link. Nothing about the
  identification itself is stored (no score, flora or date column): the rows
  written are those a search pick or a link writes.
- **Screens.** The identification screens (6b, 6c, 6f, 6g, and 6d over 6c)
  are a layer over their caller, not a route: 4d's shots live in its screen,
  and a route change releases a screen. Android back closes 6d first, then the
  layer (the back listener of
  `ui/router.ml`); 6d makes no API request. 6b never
  blocks: « Continuer sans attendre » and ← return to Noter with the photos
  (the Noter entry, superseded 2026-11-19 by M8.75: the layer is over 4k or
  4g, and 4h with M8.76);
  the request goes on, and its answer is kept with 4d's photos for the same
  photos, organs and flora, so the Identifier button opens 6c without a second
  request. Related images are `<img>` elements on `bs.plantnet.org` (an image
  needs no CORS), behind the striped loading state with « Pl@ntNet… » after
  600 ms; they are never downloaded or stored.
- **Offline, and the « À identifier » queue.** Offline (`State.network`), or
  without a key, the Identifier buttons are disabled with their reason and
  nothing is queued: a
  plant saved without a name is « À identifier » and comes back through 6i, or
  6k for a free name, by a tap once online. There is no background
  identification of the queue: each request is a tap (or, with « Identifier
  dès la photo », Enregistrer from M8.76; the first photo in Noter until
  2026-11-19), since each one costs a credit.
- **Quota and rate.** Free plan: 500 identifications a day per account, reset
  at 00:00 UTC, never billed; beyond, 429 until the reset (its `Retry-After`
  is not readable from the WebView); since 2026-02-13 a request that answers an
  error costs a credit too; at most 20 simultaneous requests per client
  (Herbier sends one at a time). Every re-ask (organ corrected, photo added,
  flora changed, no-reject, « Réessayer ») is one credit and one tap. The flora
  list (`GET /v2/projects`) is not counted.
- **Floras.** `project` is a flora id from `GET /v2/projects?lang=fr` (`id`,
  `title`, `description`, `speciesCount`), or `all`, for which Pl@ntNet picks
  the most relevant flora and names it in `preferedReferential`. Regional
  floras are Pl@ntNet's "KT" ones (POWO + WGSRPD level 2; France is in
  `k-southwestern-europe`); legacy floras run a model Pl@ntNet "will not
  update anymore". The default is `all`, « Automatique » (plan Decisions, « Flore
  par défaut », decided by Tristan on 2026-11-16: a fixed Western-Europe flora
  "would make it harder to identify non-indigenous plants"); the design's
  « Europe de l'Ouest » is replaced, and any flora of the list stays
  selectable in 4m and 6c.
- **Settings** (local, never synced; M9.66): `identify_on_photo` (« Identifier
  dès la photo », unset = on) and `plantnet_project` (the flora, compact JSON
  `{"id","title"}`, unset = `all`) in the SQLite `settings` table; the API key
  apart, in Capacitor Preferences (below). Main reads the two settings with
  the others before building the app; only the key is read after.
- **Credits and licences.** Pl@ntNet is named on every identification screen
  (tour 6's rule). Related images are "usually" CC BY-SA and must credit
  Pl@ntNet, the licence and the contributor: 6d prints « © <author> ·
  <licence> · Pl@ntNet » from each image's own `author` and `license` fields.
  The free plan does not require the "Powered by Pl@ntNet" logo ("appreciated,
  not required").
- **The API key: the user's own, typed in 4m** (plan Decisions, « Clé API
  Pl@ntNet », decided by Tristan on 2026-11-16, option C: « une clé dans les
  réglages c'est bien pour le moment »). One key per user, each with its own
  500 identifications a day; nothing in the APK, no Supabase Edge Function.
  - Stored only on the device, as the Capacitor Preferences key
    `plantnet.api_key`, not in the SQLite `settings` table: the database is in
    Android's backups, while Preferences' file is left out of them like
    `auth.session` (§4; `backup_rules.xml`, `data_extraction_rules.xml`). It
    is never synced to Supabase and never logged (above); a reinstall asks for
    it again.
  - No Supabase dependency: identification works signed out and while the
    project is paused.
  - 4m's Identification section (6h) gains a « Clé API Pl@ntNet » row the
    design does not have: the key masked, « Modifier », and a help line with a
    link to my.plantnet.org, where a key is made.
  - Exposed all the same: per Pl@ntNet's documentation a key used from a
    browser-side app must have « expose my API key » checked and the calling
    origin among its "Authorized domains"; the WebView's `fetch` sends
    `Origin: https://localhost`, so the help line asks for both, and the
    spike (§10, 7) checks it. Whoever reads the key off the phone can forge
    that `Origin` and spend the day's 500, nothing more (the free plan never
    bills; the key is regenerated in the account and pasted again).
  - Without a key, every Identifier button (6i, 6k; 6a left Noter, M8.75) is
    disabled with one
    line pointing to Réglages, as 4m's « Google Drive » radio is in a build
    without a web client id, and « Identifier dès la photo » does
    nothing. A 401 (key refused) says to check the key in Réglages.

  The options set aside (A, the key built into the APK; B, a Supabase Edge
  Function) are in `exploratory_research/plantnet-identify-api.md` §10.
