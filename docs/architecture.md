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
             gbif_key?, notes, notes_updated_at, cover_photo_id?,
             created_at, updated_at, deleted_at?
PlantRef     plant_id, source (GBIF|WIKIDATA|WIKIPEDIA|POWO|IPNI|TAXREF|TELA|
             EPPO|INAT|PLANTNET), external_id, url
Observation  id, plant_id? (null ⇒ « À identifier »), at, lat?, lon?,
             accuracy_m?, place_label?, place_derived?, note?,
             created_at, updated_at, deleted_at?
Photo        id, observation_id, taken_at, width, height, sha256,
             preview_path (device), preview_bucket_key? (Supabase Storage),
             original_target (NONE|DRIVE), drive_file_id?,
             upload_state (PENDING|UPLOADED|FAILED|ORIGINAL_MISSING),
             created_at, updated_at, deleted_at?
Tag          id, name, created_at, updated_at, deleted_at?
PlantTag     plant_id, tag_id
Reference    plant_id, source, fetched_at, payload (JSON as returned,
             lightly normalised), status (OK|PARTIAL|MISSING|ERROR)
RefImage     plant_id, source, organ?, remote_url, licence, attribution,
             thumb_path? (device, ~300 px)
```

Rules from the handoff that the model must keep: a plant may have zero
observations; an observation with no plant is "À identifier" and shows in
Journal and Carte only; free-name plants (`scientific_name = null`) are
valid and linking later fills `gbif_key`/refs and turns the free name into
an alias; deleting a photo in Herbier only unlinks, never touches Drive;
a Drive-side deletion becomes `ORIGINAL_MISSING` with the preview kept.

Derived, not stored: places. A "place" in the UI is a cluster of
observations within 500 m; a user-given name is written to `place_label` on
each observation of the cluster (handoff 4b).

## 3. Local store (device)

- `@capacitor-community/sqlite`, one database `herbier.db`, schema mirroring
  §2 plus:
  - `outbox(seq, table, row_id, op, payload_json, created_at, attempts,
    last_error)` — the sync queue.
  - `sync_state(table, last_pulled_at)`.
  - `settings(key, value)` — storage target, Wi-Fi-only, filters.
- Files under `Directory.Data`:
  - `previews/<photo_id>.jpg` (≤1600 px, q0.7 or WebP), always present.
  - `refthumbs/<plant_id>/<source>-<n>.jpg` (~300 px), evictable via
    "Libérer".
  - `tiles/<region>.pmtiles`, downloaded once from Settings.
- IndexedDB/localStorage are used for nothing durable (Android evicts them).
- Full-text search over names is done locally (SQLite FTS5 with
  `unicode61 remove_diacritics 2`), so search works offline. The Postgres
  side has the equivalent pg_trgm/unaccent index for any future web client.

## 4. Sync (outbox to Supabase)

Postgres tables `plants, plant_refs, observations, photos, tags, plant_tags`
with:

- `id uuid primary key` generated on device;
- `owner_id uuid not null default auth.uid()`, index, RLS
  `using ((select auth.uid()) = owner_id)` for `authenticated`, no anon
  policies;
- `updated_at timestamptz` maintained by the `moddatetime` trigger,
  `deleted_at timestamptz` for soft delete;
- `observations.loc geography(Point, 4326)` + GiST, kept in sync from
  `lat/lon` by trigger; an RPC `plants_near(pt, radius_m)` for "Vues ici" in
  the Noter screen (handoff 4d) when online, with a local Haversine fallback;
- `reference(plant_id, source, fetched_at, payload jsonb, status)` so the
  reference cache is also backed up, not refetched on a new device.

Protocol, run on app start, on resume, and after each local write when
online:

1. **Push**: for each outbox row in `seq` order, `POST …?on_conflict=id`
   with `Prefer: resolution=merge-duplicates` (upsert). On 2xx delete the
   outbox row; on 4xx park it with `last_error` (shown in Settings); on
   network error stop and retry later with exponential backoff.
2. **Pull**: per table, `GET …?updated_at=gt.<last_pulled_at>&order=updated_at`
   and apply with last-write-wins on `updated_at`; local rows with a pending
   outbox entry win. Update `last_pulled_at`.
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
  → read EXIF (date, GPS) with exifr, before any canvas work
  → decode with createImageBitmap (applies orientation)
  → preview: resize to ≤1600 px, encode JPEG q0.7 (or WebP), write to
    previews/<id>; insert Photo(PENDING) + outbox row
  → original: write to a temp file, enqueue in @capgo/capacitor-uploader
    (WorkManager; Wi-Fi-only if the setting says so) → Drive
    files.create (multipart) into Herbier/<scientific or display name>/
    with appProperties {herbier_photo_id, sha256}
  → on success: drive_file_id, upload_state=UPLOADED, delete temp file
  → on failure after N attempts: FAILED, badge « ↑ » stays, retry from
    Settings → « Envoyer maintenant »
```

- Drive token: `AuthorizationClient` with scope `drive.file`, requested
  lazily at the first photo to upload (handoff 4n: "Google Photos se
  connecte plus tard, à la première photo"). Tokens are 1-hour and cached by
  Play Services; the uploader plugin asks the app for a fresh one per job.
- Displaying an original (viewer, "Ouvrir dans Google Drive ↗"): open the
  `webViewLink`; the app itself only ever renders the local preview.
- Health check (weekly, when online): `files.get?fields=trashed` on a
  batch of `drive_file_id`s; `trashed` or 404 → `ORIGINAL_MISSING`.
- App-only storage target (no Google): originals are simply not kept, only
  the preview. Settings explains the ~570-photo budget if the Storage mirror
  is on.
- Google Photos: not implemented; the settings radio shows it as
  "bientôt" or is removed (open decision).

## 6. Reference pipeline

Triggered when a plant gets a `gbif_key` (link intercepted, search pick,
"Lier"), on manual ↻, or on opening the species page when online and
`fetched_at` is older than 90 days.

```
gbif_key
  ├─ GBIF  species/{k}, /vernacularNames, /distributions (WCVP rows),
  │        occurrence/count, occurrence/search?datasetKey=<Pl@ntNet>&mediaType=StillImage
  ├─ Wikidata  list=search haswbstatement:P846={k} → wbgetentities
  │            → P5037/P961 POWO/IPNI, P3186 TaxRef, P3105 Tela, P3031 EPPO,
  │              P3151 iNat, sitelinks fr/en/de/it
  ├─ Wikipedia REST page/summary/{fr title} (fallback en)
  └─ regional layer (if enabled):
       Tela  bdtfx/noms?masque={name} → nn, cd_nom
             bdtfx/taxons/{nn} (statut origine/introduction), baseflor
             (type_bio, floraison, écologie), coste (description), del images
       INPN  odata-inpn /taxa/{cd_nom}, /protections/articles/entries,
             /redLists/entries
```

- Each call writes its own `reference` row (source, payload, status), so a
  failing source never blanks the others and every row in the UI cites its
  source (handoff 4f: "Une ligne sans donnée disparaît. Toute donnée cite sa
  source.").
- The species page reads a **projection** of the reference rows into the
  handoff's `ReferenceSnapshot` fields (vernacular per language, family, life
  form, native/introduced range, FR status, protection, red list, flowering
  months, habitat/ecology chips, toxicity, organ photos, links). Altitude is
  dropped; height is parsed from Coste text when present.
- Organ photos: four thumbnails (fleur/feuille/fruit/port) picked from the
  GBIF Pl@ntNet dataset media by `title` suffix, downloaded to `refthumbs/`
  with licence and attribution kept for display.
- Distribution map on the species page: GBIF density tiles
  `v2/map/occurrence/density/{z}/{x}/{y}@1x.png?taxonKey=` over the base
  map; attribution GBIF.
- All requests carry `User-Agent: Herbier/<version> (<contact>)`; Wikimedia
  without it is limited to 10 req/min.
- Reference fetches go through a small **rate-limited queue** (one source at
  a time, ≤3 concurrent overall) since we call several public APIs at once.

## 7. Link interception and resolution

Manifest `intent-filter`s (`VIEW` + `BROWSABLE`, `https`):
`www.gbif.org/species/*` and `/{lang}/species/*`,
`identify.plantnet.org/*/species/*` and `/*/observations/*`,
`*.wikipedia.org/wiki/*`, `powo.science.kew.org/taxon/*`,
`inpn.mnhn.fr/espece/cd_nom/*` and `/explorer/especes/*`,
`www.tela-botanica.org/bdtfx-nn-*`, `www.inaturalist.org/taxa/*`.
Plus `SEND text/plain` via the share-target plugin. On Android 12+ the user
enables these once under "Ouvrir par défaut" (no Digital Asset Links since we
do not own these domains); the share sheet path needs nothing.

Resolver (OCaml, shared by screens 4i/4j/4k/5c):

```
input (URL or text)
  → classify by host/pattern
     gbif       → key from path
     plantnet   → decode "Genus species Author" from path → GBIF species/match
     wikipedia  → REST summary → wikibase_item → Wikidata P846
     inpn/tela  → cd_nom / nn → name → GBIF species/match
     powo/inat  → Wikidata by P5037/P3151 → P846
     free text  → GBIF species/suggest + search?qField=VERNACULAR
  → gbif_key + immediate partial snapshot (canonical name, family)
  → screen 4j pre-filled; full reference fetch in background after save
```

What the Pl@ntNet app actually puts in a share (URL vs text) is unverified;
the classifier must accept both a bare URL and text containing one.

## 8. Map

- MapLibre GL JS behind a JS facade (`map.js`, ~100 lines) exposing: create,
  set style, set GeoJSON source, on click/moveend, getCenter, flyTo, add
  metric circle. Bound from OCaml with Brr `Jv`.
- Sources: observations as a GeoJSON source with `cluster: true`; the 500 m
  semantics come from a **pre-clustering step in OCaml** (grid/Haversine) at
  low zooms, MapLibre clustering only merges overlapping markers on screen.
- Styles: OpenFreeMap `positron` online; offline, the same style with the
  tile source swapped to `pmtiles://` pointing at `tiles/<region>.pmtiles`
  (Protomaps `@protomaps/basemaps` flavour `white`). Switch is automatic on
  connectivity change.
- GPS accuracy: a metric circle layer (radius in metres, zoom-dependent
  pixels), never a number in the UI (handoff 4h).
- Mini-map (observation screen): a non-interactive MapLibre instance, or a
  cached PNG rendered once from it.
- Reverse geocoding for `place_derived`: Photon (or Géoplateforme in France),
  called once per observation when online, cached in the row.

## 9. Repository layout (proposed)

```
herbier/
  dune-project
  app/            OCaml sources (js_of_ocaml)
    ui/           rb.ml (react↔Brr glue), screens, tokens.ml (design tokens)
    store/        sqlite bindings, schema migrations, outbox
    sync/         PostgREST client, pull/push
    photos/       exif, compress, drive client, uploader binding
    reference/    per-source clients, projection, rate limiter
    resolver/     link/text → gbif_key
    map/          maplibre facade bindings
    capacitor/    plugin bindings (Jv)
  web/            static shell: index.html, css, fonts, map.js, built app.js
  android/        Capacitor project (generated), manifest intent-filters
  supabase/       migrations, RLS, RPC functions, config
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
3. **Map spike**: MapLibre in the WebView with OpenFreeMap positron, then a
   PMTiles file read from the filesystem through the `pmtiles` protocol,
   offline. This is the "painful" item; if filesystem-backed PMTiles fails,
   fall back to an `addProtocol` write-through cache of visited tiles.
4. **Auth spike**: Credential Manager sign-in → Supabase `signInWithIdToken`;
   `AuthorizationClient` for `drive.file`; confirm the OAuth client can be
   "In production" with no verification prompt.
5. **Reference spike**: run the §6 pipeline for two species from OCaml and
   render the projection; measure how many fields come back empty.
6. **UI spike**: write the `rb.ml` glue (react + ReactiveData over Brr),
   then screen 4a (Collection: tag chips, search, grid) and the bottom sheet
   drag as a signal-bound transform. Check that leaving and re-entering the
   screen releases every binding (no stale updates, no growth in
   `performance.memory`). If it disappoints, redo 4a in ocaml-vdom and
   compare.

## 11. Non-goals restated

No identification, no sharing, no multi-user, no Google Photos (for now),
no server-side rendering, no push notifications, no Play Store listing
required (sideload is fine; Play's target SDK rules do not apply).
