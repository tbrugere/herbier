# Herbier — Architecture proposal

Status: proposal, 2026-09-15. Companion to `stack.md` (which layer uses
what) and to the design handoff in `design_handoff_herbier/README.md`
(screens, tokens, the original data model). This file says how the pieces
fit and what the data looks like end to end.

## 1. Big picture

```
┌──────────────────────────── Android device ─────────────────────────────┐
│  Capacitor shell (Kotlin: manifest intent-filters, plugins)              │
│  ┌───────────────────────── WebView ─────────────────────────────────┐  │
│  │  OCaml app (js_of_ocaml + Brr + react/ReactiveData)               │  │
│  │   ├─ UI (screens 4a–5f)            ├─ Reference pipeline (§6)     │  │
│  │   ├─ Store (local SQLite, §3)      ├─ Photo pipeline (§5)         │  │
│  │   ├─ Outbox / sync (§4)            ├─ Link resolver (§7)          │  │
│  │   └─ Map (MapLibre facade, §8)                                    │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│  App-private files: previews/, reference thumbs/, region.pmtiles        │
│  WorkManager (via @capgo/capacitor-uploader): Drive uploads             │
└─────────────────────────────────────────────────────────────────────────┘
        │ PostgREST (JWT)         │ Drive API (1h token)      │ GET, keyless
        ▼                         ▼                           ▼
  Supabase Free            Google Drive               GBIF · Wikidata · Tela
  (Postgres + RLS,         Herbier/<species>/…        INPN odata · Wikipedia
   optional Storage        originals                  OpenFreeMap tiles
   bucket for previews)                               Photon / Géoplateforme
        ▲
        │ supabase db dump, twice a week (GitHub Actions, committed to a
        │ separate private backups repo) = backup + keep-alive
```

Principles:

- **Device is the source of truth.** Every screen renders from local SQLite.
  The network is only used to sync, to fetch reference data, to upload
  originals and to draw map tiles outside the offline extract.
- **Nothing blocks on the network.** Recording, browsing, editing work
  offline; "Lier", reference search and refresh are disabled offline with a
  visible reason (handoff 4g/4i).
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
             preview_path (device), preview_bucket_key? (Supabase Storage),
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
an alias; deleting a photo in Herbier only unlinks, never touches Drive;
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
  - `settings(key, value)` — storage target, Wi-Fi-only, filters. Keys are
    typed (`store/settings.ml`, a GADT): `storage_target` (the
    `photo_original_target` label) and `wifi_only` (`true` / `false`) so
    far; a value that does not parse is a decode error, not a silent
    default.
- Local column types (`store/schema.ml`, migration 1): ids, lookup values
  and text are `text`; timestamps are `text` in one fixed-width UTC format with
  microseconds (`Codec.timestamp`), so text order is time order; `text[]`
  and `jsonb` columns are `text` holding JSON, parsed back by
  `Codec.decode ~json` before `Postgrest.Row`; `double precision` is `real`.
  Foreign keys and the position checks mirror the server, except
  `plants.cover_photo_id` (it would close a cycle with `photos` and break a
  first pull). A cover that points at a deleted or not yet pulled photo is
  read as no cover: the plant's newest live photo stands in
  (`app/ui/cover.ml`). The four lookup tables (§2) exist locally too, with the same
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
  its `organ` column references. The schema version is SQLite's `user_version`; a file at a
  version above the app's is refused, not migrated. A migration is a list of
  statements (`Schema.migration`), applied with its `user_version` bump in one
  transaction by the plugin's `executeSet`, which prepares each string as
  given; the plugin's `execute` splits its text on `;` and newline, so it is
  used only for single statements.
- Files under `Directory.Data`:
  - `previews/<photo_id>.jpg` (≤1600 px, q0.7 or WebP), always present.
  - `refthumbs/<plant_id>/<source>-<organ>.jpg` (shorter side ≤300 px, JPEG
    q0.8), evictable via "Libérer". A changed image for an organ overwrites
    the same file: the row's `thumb_path` is cleared first and set again only
    if the row still holds the downloaded URL (the syncs of one plant never
    overlap). The thumbnails of a deleted plant stay until "Libérer" sweeps
    `refthumbs/` against `ref_images`.
  - `tiles/<region>.pmtiles`, downloaded once from Settings.
- The binding (`Cap_sqlite.query`) returns each row as the JSON text of the
  plugin's row object; `store/db.ml` parses it and decodes it with
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
  Settings, pull and the dev seed write without entries (pull and the seed
  through `Outbox.without_entry`). That the bare statement is used only there
  is a convention, not a type: `Db.write` accepts it. `seq` has no `autoincrement`, so a number may
  be reused once the newest entry is deleted: the sync engine must not hold a
  `seq` across a `delete`.
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
  natural key and reuses its `id`, so push stays `on_conflict=id` for every
  table and the outbox keeps one `row_id` per row. A new row of these three
  tables gets an id derived from its natural key (UUID v5 of `plant_id` and
  `tag_id` or `source`, under the Herbier namespace
  `b85c6db9-9479-4fb1-af57-3ff6ad665b62`, of the name
  `<table>/<plant_id>/<tag_id or source>` in canonical lowercase, e.g.
  `plant_tags/<plant_id>/<tag_id>`; `Ids.Plant_tag_id.of_key`,
  `Ids.Plant_ref_id.of_key`, `Ids.Reference_id.of_key`), not a random one:
  two installs that create the same link before syncing produce the same
  id, so the second push merges instead of failing on the unique constraint;
- server-only columns, `owner_id` (defaulted to the caller) and
  `observations.loc` (set by the trigger), carry `metadata: server_only`
  in their column comment and are left out of the generated
  `app/store/tables.ml`: the app never sends or reads them;
- foreign keys are checked without RLS, so a row may reference another
  owner's row by id. Accepted: there is one account and sign-ups are off.

`updated_at` has no default and the device always sends it, as its local
last-write-wins clock, but the server's `set_updated_at` trigger replaces it
by server time (`now()`) on every insert and update. The pull cursor
therefore never compares a device clock: a row created offline and pushed
hours later still sorts after every other install's last pull. The device
adopts the server value from the push response (`Prefer:
return=representation`) or the next pull. `now()` is the transaction start,
so a long transaction can commit behind a cursor already advanced; the pull
asks for a few seconds of overlap (`updated_at=gt.<last_pulled_at - 5 s>`),
which LWW makes idempotent.

The local store keeps timestamps to the microsecond, as `timestamptz` does,
but `Postgrest.Col` encodes a `TimestampTz` with whole seconds
(`Ptime.to_rfc3339` without `~frac_s`), so until that encoder passes
`~frac_s:6` a pushed `created_at`, `at` or `notes_updated_at` loses its
fractional digits and the next pull brings back the truncated value.
`updated_at` is unaffected (the server sets it).

Protocol, run on app start, on resume, and after each local write when
online:

1. **Push**: for each outbox row in `seq` order, `POST …?on_conflict=id`
   with `Prefer: resolution=merge-duplicates` (upsert). On 2xx delete the
   outbox row; on 4xx park it with `last_error` (shown in Settings); on
   network error stop and retry later with exponential backoff. Foreign keys
   are not deferrable, so `seq` order (parents first) is load-bearing and a
   parked row also parks the rows that reference it.
2. **Pull**: per table, `GET …?updated_at=gt.<last_pulled_at - overlap>&order=updated_at`
   and apply with last-write-wins on `updated_at`; local rows with a pending
   outbox entry win. Update `last_pulled_at`. Local foreign keys are
   enforced, and a parent created elsewhere between the pull of its table and
   the pull of its child's table reaches the device after the child. So the
   tables are applied parents first (plants, tags, observations, photos, then
   the link and reference tables) in one transaction with `pragma
   defer_foreign_keys = on`; if the commit fails on a foreign key, the whole
   pull rolls back with its cursors and the next cycle, which now sees the
   parent, retries.
3. Previews: if the private Storage bucket is enabled, upload
   `previews/<id>.jpg` missing remotely; download missing locally on demand
   (new device case).

Pausing: if PostgREST answers with the paused-project error, the outbox just
waits; the user sees "serveur en pause" in Settings with a link to the
dashboard. Recording is unaffected.

Auth on device: Google sign-in via Credential Manager → `signInWithIdToken`
on Supabase → session in Capacitor Preferences; `startAutoRefresh` on
resume, `stopAutoRefresh` on background.

## 5. Photo pipeline

```
capture / pick
  → read EXIF (date, GPS) with exifr, before any canvas work; the Android
    system photo picker empties the GPS tags of a picked copy (seen on the
    emulator, API 35)
  → decode with createImageBitmap (applies orientation)
  → preview: resize to ≤1600 px, encode JPEG q0.7 (or WebP), write to
    previews/<id>; insert Photo(pending) + outbox row
  → original: write to a temp file, enqueue in @capgo/capacitor-uploader
    (WorkManager; Wi-Fi-only if the setting says so) → Drive
    files.create (multipart) into Herbier/<scientific or display name>/
    with appProperties {herbier_photo_id, sha256}
  → on success: drive_file_id, upload_state=uploaded, delete temp file
  → on failure after N attempts: failed, badge « ↑ » stays, retry from
    Settings → « Envoyer maintenant »
```

- Drive token: `AuthorizationClient` with scope `drive.file`, requested
  lazily at the first photo to upload (handoff 4n: "Google Photos se
  connecte plus tard, à la première photo"). Tokens are 1-hour and cached by
  Play Services; the uploader plugin asks the app for a fresh one per job.
- Displaying an original (viewer, "Ouvrir dans Google Drive ↗"): open the
  `webViewLink`; the app itself only ever renders the local preview.
- Health check (weekly, when online): `files.get?fields=trashed` on a
  batch of `drive_file_id`s; `trashed` or 404 → `original_missing`.
- App-only storage target (no Google): originals are simply not kept, only
  the preview. Settings explains the ~570-photo budget if the Storage mirror
  is on.
- Google Photos: not implemented; the settings radio offers Drive and
  app-only, no Google Photos row.

## 6. Reference pipeline

Triggered when a plant gets a `gbif_key` (link intercepted, search pick,
"Lier"), on manual ↻, or on opening the species page when online and the
plant's rows are due (`refs/fanout.ml`): a fetched source without a live row,
a row older than 90 days, or a `failed`/`partial` row older than one day (so
one bad connection does not leave the fiche empty for three months). The due
check runs once per entry into the fiche, never on the reloads the fetch
itself causes.

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
  taxon's rows under the new key. The plant's non-GBIF `plant_refs` are left
  as they are (open point, settled with 5a's « Liens de référence »).
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
  (`refs/projection.ml`) reads whatever parts a row holds, whatever its
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

Manifest `intent-filter`s (`VIEW` + `BROWSABLE`, `https`), one per host
below; the resolver classifies exactly the same hosts:
`www.gbif.org` and `m.gbif.org`: `/species/*` and `/{lang}/species/*`;
`identify.plantnet.org`: `/*/species/*` and `/*/observations/*`;
`plantuse.plantnet.org`, `uses.plantnet.org` and the old
`uses.plantnet-project.org`: `/*` (the Pl@ntUse wiki, linked from Pl@ntNet
species pages; which host is current is to verify);
`*.wikipedia.org` (and `*.m.wikipedia.org`): `/wiki/*`;
`powo.science.kew.org`: `/taxon/*`;
`inpn.mnhn.fr`: `/espece/cd_nom/*` and `/explorer/especes/*`;
`www.tela-botanica.org`: `/bdtfx-nn-*`;
`www.inaturalist.org` and `m.inaturalist.org`: `/taxa/*`.
Plus `SEND text/plain` via the share-target plugin. On Android 12+ the user
enables these once under "Ouvrir par défaut" (no Digital Asset Links since we
do not own these domains); the share sheet path needs nothing. Both paths
ship in v1.

Resolver (OCaml, shared by screens 4i/4j/4k/5c):

```
input (URL or text)
  → classify by host/pattern
     gbif       → key from path
     plantnet   → decode "Genus species Author" from path → GBIF species/match
     plantnet observation → no name in the path, and Pl@ntNet's API needs a key:
                  4i fallback with an empty query
     plantuse   → "Genus_species" wiki page name → GBIF species/match (host to verify)
     wikipedia  → REST summary → wikibase_item → Wikidata P846
     inpn/tela  → Wikidata by P3186/P3105 → P846 (not the regional APIs; gaps → 4i)
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
  click/moveend/idle/error, getCenter, getZoom, flyTo, fit bounds (capped at a
  maximum zoom), rendered ids, resize, remove. Bound from OCaml with Brr `Jv`;
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
  the accuracy circle (`Widgets.Mini_map`); tapping it opens 4b centred on the
  observation, through a one-shot framing in `State.map_view`.
- Reverse geocoding for `place_derived`: Photon (or Géoplateforme in France),
  called once per observation when online, cached in the row.

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
    photos/       exif, compress, drive client, uploader binding
    reference/    per-source clients, projection, rate limiter
    resolver/     link/text → gbif_key
    map/          maplibre facade bindings
    capacitor/    plugin bindings (Jv)
  web/            static shell: index.html, sass, fonts, map.js; Capacitor webDir → _build/default/web/dist
  android/        Capacitor project (generated), manifest intent-filters
  supabase/       hand-written migrations, schema dump, RLS, RPC functions, config
  docs/
herbier-backups/  (separate private repo)
  .github/workflows/backup.yml   supabase db dump cron (keep-alive + backup)
  roles.sql schema.sql data.sql  committed by the workflow
```

## 10. Spikes before committing to the stack

Each is one or two days and answers a question the reports left open.

1. **Shell spike**: jsoo + Brr "hello" in Capacitor 8; share-target receives
   a Pl@ntNet URL; a `VIEW` filter on `gbif.org` opens the app after
   enabling it in "Ouvrir par défaut"; `@capgo/capacitor-uploader` uploads a
   file to Drive with the app swiped away, on Wi-Fi only. Pass = Capacitor
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

## 11. Non-goals restated

No identification, no sharing, no multi-user, no Google Photos (for now),
no server-side rendering, no push notifications, no Play Store listing
required (sideload is fine; Play's target SDK rules do not apply).
