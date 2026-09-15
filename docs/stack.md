# Herbier — Stack

Status: proposal, 2026-09-15. Derived from the six reports in
`exploratory_research/` (each has a dated Summary on top). Where this file
and a report disagree, this file is the decision and the report is the
evidence. Open decisions are listed at the end.

## Reality check on the original idea

| Original idea | Verdict | Why (see report) |
|---|---|---|
| Eliom + Cordova front | **Dropped** | Eliom is alive but its Cordova template is fossilised (2016–2017 plugins, Node 10, "android-26+ may not work"); the Ocsigen team said in June 2026 it is moving to Capacitor and that offline apps are unfunded; an Eliom mobile app needs a version-locked ocsigenserver, which Supabase makes pointless. `front-stack-eliom-cordova.md` |
| Cordova as the shell | **Dropped for Capacitor** | Cordova core is maintained (cordova-android 15) but every non-core plugin we need (share receiver, App Links, Google auth, background upload) is dead there and has 2026 releases on Capacitor. Capacitor packages any folder of static JS, so js_of_ocaml output drops in unchanged. |
| Supabase free tier backend | **Kept, as sync + backup target** | Fine for one user, but projects pause after 7 days without user DB activity. The device is the source of truth; Supabase is where data is mirrored. `backend-supabase-offline.md` |
| Google Photos for originals | **Deferred; Google Drive first** | Every Photos scope requires OAuth verification, URLs expire after 60 min, no delete API, picked items can't be re-fetched. Drive's `drive.file` scope is non-sensitive: no verification, no 7-day token expiry. `photo-storage-google.md` |
| Google Maps / OSM tiles | **Neither** | OSM's tile server forbids offline/bulk use; Google needs billing, gives 10k loads/month and has WebView quirks. Keyless vector tiles from OpenFreeMap plus an on-device PMTiles extract. `maps-tiles-geocoding.md` |

## Chosen stack

### Language and UI: OCaml via js_of_ocaml, packaged with Capacitor

- **js_of_ocaml 6.x** compiles the whole app to JS. `wasm_of_ocaml` is
  available but unnecessary.
- **Brr** for browser APIs (DOM, fetch, canvas, geolocation, media) and the
  `Jv` FFI for the handful of JS libraries we bind by hand (MapLibre, the
  Capacitor plugins).
- **UI layer: fine-grained reactivity with ocaml-react + ReactiveData over
  Brr** (decided 2026-09-16). State lives in `react` signals; DOM attributes,
  text and child lists are bound to signals through a small glue module we
  write ourselves (~150 lines, see "UI components" below). ReactiveData
  provides incremental list patches. No virtual DOM. Fallback if the
  reactive approach disappoints in the UI spike: ocaml-vdom (Elm
  architecture, one state value, diffing). Rejected: Note + `note.brr`
  (self-described experimental, "will break"), Bonsai (too heavy),
  Tyxml_js.R (ready-made glue but a second DOM binding next to Brr),
  Melange + reason-react (second toolchain, only worth it for npm widgets).
- **Capacitor 8** as the Android shell. Plugins we depend on (all with 2026
  releases): `@capacitor/app` (deep links), `@capgo/capacitor-share-target`
  (SEND share sheet), `@capgo/capacitor-social-login` or
  `@capawesome/capacitor-google-sign-in` (Credential Manager +
  AuthorizationClient), `@capgo/capacitor-uploader` (WorkManager background
  upload), `@capacitor-community/sqlite`, `@capacitor/filesystem`,
  `@capacitor/geolocation`, `@capacitor/camera` (gallery pick). Camera
  viewfinder via `getUserMedia` in the WebView, with
  `@capacitor-community/camera-preview` as fallback.
- A **small Kotlin layer** is expected: the `intent-filter`s in the manifest
  and possibly a WorkManager tweak. Nothing else native.
- Screens from the design handoff are recreated in HTML/CSS from OCaml, not in
  Jetpack Compose as the handoff README assumes. Design tokens (colours,
  type, spacing) carry over as-is; Material Symbols and the two Google Fonts
  are bundled.

Why not the two runners-up (see `ocaml-android-stacks.md`):

- **PWA in a Trusted Web Activity** keeps ~95% OCaml and avoids the WebView,
  but loses guaranteed background upload (one-shot Background Sync only),
  silent capture of `gbif.org` links (needs a Kotlin activity anyway) and
  durable storage (`persist()` is unreliable). Same OCaml code moves to a
  TWA later if Capacitor disappoints; keep the JS bundle shell-agnostic.
- **Native OCaml core (opam-cross-android reboot, OCaml 5.4.1) + Compose
  UI** is credible since August 2026 but the JNI embedding is unverified,
  eio/ctypes/sqlite3 are not cross-built yet, and it drops to 30–50% OCaml.
  Worth a two-day spike for fun, not the main line.
- **Qt via lablqml**: lablqml 0.7 (2021) needs OCaml < 5 and Qt 5; its Android
  branch is from 2017. Reviving three layers before writing any UI. No.

### UI components

- **Pure HTML5 and CSS with the design tokens, no component library.** The
  design is fully custom (paper/moss palette, Manrope and Newsreader, custom
  tab bar), so Ionic, Material Web (maintenance mode since 2024) or Shoelace
  would be fought rather than used. The widget inventory is small: buttons,
  chips, cards, list rows, tab bar, radios/switches, text fields, month
  grid, photo grid, bottom sheet, slide-up modal, photo viewer.
- Several interactions are CSS only on a modern WebView: swipe between
  photos and pager-style grids via `scroll-snap`, sheets and tab bar via
  `position: sticky` and `<dialog>`, shared-element transitions via the View
  Transitions API (Chrome 111+, plain fade as fallback).
- Three pieces are imperative and hold JS-library state: the MapLibre map,
  the camera `<video>`, the pinch-zoom viewer. With signals they need no
  special "island" machinery: the widget subscribes to a signal
  (`S.map (fun pts -> Map.set_data map pts) observations`, kept in the
  screen's binding list) like any DOM node. Per-frame work such as the bottom-sheet drag is a `float`
  signal bound to a `style` attribute.
- **The glue module** (`app/ui/rb.ml`, our own): `text`, `attr`, `class_`,
  `style` bind one DOM property to a signal; `children` replaces a child
  list from a signal; `rlist` applies ReactiveData patches (insert, remove,
  update, move) with `El.insert_siblings`/`El.remove`; `ev` turns a Brr DOM
  event into a `react` event; `release` strongly stops a screen's bindings.
  Every binding is collected by its screen and released with
  `S.stop ~strong:true` / `E.stop ~strong:true` when the screen is torn
  down. On js_of_ocaml weak arrays are strong, so react never collects a
  binding by accident (the classic native pitfall); the risk is the
  opposite, leaks, and the release rule is what prevents them. See
  `notes/ocaml-react-primer.md`.
- Known costs, accepted: state is spread across signals rather than one
  value (snapshotting for debugging is manual); setters must not be called
  during a propagation step; no compile-time HTML structure checks (TyXML
  would give those).

### Capability ratings for the chosen stack

easy: gallery pick, GPS, share-sheet receiver, local SQLite + filesystem,
image compression, fonts, Supabase/PostgREST over fetch.
doable: custom viewfinder, MapLibre map and clusters, VIEW deep links
(user must enable "Open by default" on Android 12+, same as a Kotlin app),
background upload (network-constraint options unverified), transitions,
gestures, zoomable viewer.
painful: offline tiles (OPFS/filesystem-backed PMTiles in the WebView is
unverified), Google OAuth (solved only via Credential Manager plugin).
blocked: nothing.

### Backend: Supabase Free, local-first

- **Device SQLite is the source of truth**; previews live in the app-private
  filesystem (`Directory.Data`). WebView storage (IndexedDB, localStorage,
  OPFS) is evictable on Android and is not used for anything durable.
- **Supabase Free** mirrors the data through PostgREST with a hand-rolled
  **outbox**: UUID primary keys generated on device, `updated_at` maintained by
  `moddatetime`, soft delete via `deleted_at`, last-write-wins. Third-party
  sync engines (PowerSync, ElectricSQL, RxDB, WatermelonDB, Legend-State) all
  need logical replication or paid storage and an always-unpaused project.
- Free-tier numbers (2026-09-15): 500 MB DB, 1 GB storage (50 MB/file),
  5 GB egress, 2 projects, no backups, image transforms Pro-only. PostGIS,
  pg_trgm, unaccent and pg_cron are available on Free.
- **Pausing**: inactive after 7 days without user DB activity; one-click
  restore with data intact for up to a year. A **GitHub Actions cron running
  `supabase db dump` twice a week** is both the backup and the keep-alive
  (pg_cron alone is reported not to count, unverified). GitHub Free includes
  2,000 Actions minutes/month for private repos; the job needs a minute or
  two. The dump (`roles.sql`, `schema.sql`, `data.sql`) is committed to a
  **separate private repository** (it contains coordinates and notes), so
  the app repo can be public. The dump does not cover Storage bucket files;
  previews stay on device and originals on Drive, so nothing is lost.
- **Auth**: one Google sign-in on the device through Credential Manager,
  passed to Supabase with `signInWithIdToken`; the same plugin's
  `AuthorizationClient` grants the `drive.file` scope and hands out 1-hour
  access tokens cached by Play Services, so no refresh token is stored by
  us. Sign-ups disabled in Supabase; RLS `owner_id = (select auth.uid())`.
  Fallback: email+password.
- Pro ($25/month) only buys "never paused" and backups. Not needed.

### Photos: Google Drive first, previews everywhere, Photos deferred

- **Originals → Google Drive**, scope `drive.file`, folder
  `Herbier/<species>/`, one file per original with `appProperties` carrying
  the Herbier photo id and content hash. Deletion on the Drive side shows as
  `trashed:true` then 404 → `ORIGINAL_MISSING`. Thumbnails via
  `thumbnailLink` (`=s1600` variant, community-documented). Counts against
  the account's shared 15 GB.
- **Preview** (≤1600 px, JPEG q0.7 or WebP, 150–250 KB target) is always
  kept on device, and optionally mirrored to a private Supabase Storage
  bucket. Note 1600 px JPEG at q80 is 300–500 KB in practice, so the design's
  "200 MB app-only" option holds ~570 photos, not thousands.
- Canvas-based compression strips EXIF; read GPS and capture date once (e.g.
  with `exifr`) into the observation row before compressing.
- **Google Photos Library / Picker: deferred.** Needs OAuth verification for
  any scope, 10k requests/day, 60-minute URLs, no delete. The user's normal
  camera-roll backup already puts originals in Google Photos anyway.
- **Overflow beyond 15 GB**: Cloudflare R2 (10 GB free, free egress, then
  ~$0.015/GB-month) via presigned URLs from a Supabase Edge Function.
- OAuth client stays a personal one, published "In production" with only
  non-sensitive scopes, so no verification and no 100-user cap issue.

### Botanical reference data

- **Primary key: GBIF backbone `usageKey`.** Every entry path resolves to it:
  a GBIF link directly; a Pl@ntNet link carries "Genus species Author" →
  `species/match`; a Wikipedia link → REST summary → Wikidata P846; free
  text → `species/suggest` (scientific) + `species/search?qField=VERNACULAR`.
- **Wikidata as the cross-id hub** (`haswbstatement:P846=<key>` then
  `wbgetentities`): POWO/IPNI, TaxRef, Tela Botanica, EPPO, iNaturalist ids and
  sitelinks in fr/en/de/it. TaxRef coverage on Wikidata is only ~31%, so
  Tela's `bdtfx/noms?masque=` (returns `cd_nom`) is the TaxRef bridge.
- **Per-field sources** (all keyless, all free):
  GBIF (taxonomy, vernaculars, WCVP distributions, occurrence count and
  density map tiles), Tela Botanica eFlore/Baseflor (life form, flowering
  months, ecology, French status, Coste description, images), INPN
  `odata-inpn.mnhn.fr` (French vernaculars, protection, red list; undocumented
  HAL API, the official TaxRef API is currently redirecting to the web UI),
  Wikipedia REST summary fr→en (description, toxicity heuristic), Pl@ntNet
  images by organ through **GBIF's Pl@ntNet occurrence dataset** (CC BY-SA)
  rather than Pl@ntNet's own pages (terms forbid copying, pages rate-limit).
- **Not obtainable**: structured altitude range. **Partial**: native vs
  introduced range (WCVP gaps, POWO's JSON API is Cloudflare-blocked),
  height (parsed from Coste prose), toxicity (heuristic).
- **Regional layer**: INPN and Tela Botanica are France-specific. They are a
  pluggable "regional" enrichment, since the user's region is not fixed; the
  design's "En France" row only renders when that layer applies.
- Wikimedia requires a descriptive User-Agent (200 req/min with one, 10
  without). GBIF wants one too.

### Maps

- **MapLibre GL JS 6** (WebGL2, ~150 KB gz), bound by hand from OCaml through a
  ~100-line JS facade. Leaflet has opam bindings but 2.0 is alpha and raster is
  worse offline.
- **Online tiles**: OpenFreeMap `positron` style (no key, no stated limits),
  with the design's CSS desaturation if wanted. Keyless fallbacks: VersaTiles,
  IGN Plan IGN vector (France). Keyed fallbacks: Protomaps hosted (1M
  req/month), Stadia, Thunderforest.
- **Offline**: one Protomaps **PMTiles extract of the user's region** stored
  on device and read through the `pmtiles` protocol. Order of magnitude for a
  two-department area: ~60 MB at z≤12, ~240 MB at z≤14. No service worker
  (flaky in the Android WebView). Never cache `tile.openstreetmap.org`.
- **Geocoding**: forward search with **Photon** (komoot; autocomplete allowed);
  reverse with Photon too, or **IGN Géoplateforme** when in France (keyless,
  better rural place names). Nominatim excluded by its usage policy.

## Cost

Everything above is $0/month at one user's volume. The only paths to a bill
are Cloudflare R2 beyond 10 GB of originals and Supabase Pro, both optional.

## Open decisions (for Tristan)

1. **Region** for the offline PMTiles extract and whether the France-only
   sources (INPN, Tela, IGN) are worth wiring at all. The handoff's
   Alsace/Vosges examples are placeholders.
2. **Google account**: a personal Gmail is assumed. A Workspace account would
   make the OAuth app "internal" and lift all verification questions, but is
   unnecessary with `drive.file` only.
3. **Keep the Google Photos option in the settings screen** as "coming later",
   or remove it from the design.
4. **Two devices later?** The outbox design tolerates it (LWW), but conflict
   handling stays naive on purpose.
