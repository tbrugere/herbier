# Herbier — Implementation plan

Status: proposal, 2026-09-16. Orders the work needed to reach the mockup
(`design_handoff_herbier/README.md`, screens 4a–4n and 5a–5f) with the
modules of `layout.md`, the decisions of `stack.md` and the design of
`architecture.md`. The six spikes of architecture §10 are absorbed as the
first steps of the milestone that needs them: spike 1 (shell) → M0.4, M4.38,
M7.52; spike 2 (storage) → M2.14, M2.16, M3.25; spike 3 (map) → M5.39,
M5.44; spike 4 (auth) → M6.46, M7.51; spike 5 (references) → M4.33;
spike 6 (UI) → M1.

Conventions: one step = what gets written · what it depends on · done when.
Screen ids refer to the handoff; a screen is "functional" when it renders
from the local store and every action on it that does not need a later
milestone works. Each milestone ends in something runnable in a browser
(`dune build @web` + a static server) or on the phone (`scripts/dev.sh`).

## M0 — Toolchain (runnable: hello page in browser and on phone)

1. `dune-project` (package `herbier`: js_of_ocaml, brr, react, reactiveData, yojson, ptime, uuidm, alcotest), `dune pkg lock` with `dune.lock/` committed, `.ocamlformat`. Done: `dune build` from a clean clone with only dune installed.
2. `app/dune`, `app/main.ml` (`(modes js)`), `app/domain/dune` also built natively, `test/domain/` with one alcotest. Done: `dune test` passes; layout §2 dependency direction is in the `libraries` fields.
3. `web/index.html`, `web/dune` (`@web` alias → `_build/default/web/dist`), `package.json` with esbuild, empty `web/js/vendor.js` bundle. Done: serving `dist/` shows a "Herbier" heading written by Brr.
4. `npx cap init` + `npx cap add android`, `capacitor.config.ts` with `webDir` into `_build`, `android/` committed, `scripts/dev.sh`. Done: the same page on the phone through `cap run android -l` (spike 1, part 1).
5. `.github/workflows/ci.yml` (build, test, `fmt --check`) and `android.yml` (debug APK artifact). Done: green run on `main`; APK downloadable and sideloadable.

## M1 — UI foundation (spike 6; runnable: 4a from fixtures in the browser)

6. `ui/rb.ml` + `.mli` per primer §6: `text`, `attr`, `class_`, `style`, `children`, `rlist`, `ev`, `release`. Depends: M0. Done: a toy page with a counter, a class toggle and an `RList` of rows; `release` stops updates.
7. `ui/tokens.ml` + dune rule emitting `web/css/tokens.css`; `base.css` (`@font-face`, type scale, 5f rules); `fonts/` (Manrope, Newsreader, `scripts/subset-icons.sh`). Done: a dev route shows every colour and type role of the handoff.
8. `ui/widgets/` chip, card, list_row, tab_bar, icon, text_field; `widgets.css`. Done: each widget has a fixture entry on a dev "gallery" route.
9. `ui/router.ml` (route variant, `S.bind` on the current screen, release of the previous screen) and `ui/state.ml` (filters, network, account). Done: switching tabs tears the old screen down; binding count back to baseline.
10. `screens/collection.ml` (4a) over `test/fixtures/` plants: title + counter, search filtering an `RList`, tag chips, 2-column grid. Done: search and chip filter patch the grid (only touched cards re-rendered).
11. `widgets/sheet.ml`: bottom sheet whose drag is a `float` signal bound to `transform`, snap points. Done: 60 fps drag on the phone, no per-frame allocation visible in DevTools.
12. Spike exit criterion: enter/leave 4a fifty times; no stale updates, `performance.memory` flat, no dropped frames on the sheet. **Fallback trigger**: either check still fails after one day of fixing, or `rb.ml` needs more than ~300 lines to stay correct → redo 4a in ocaml-vdom, compare, update `stack.md` either way.

## M2 — Local data (spike 2; runnable: offline app with records, no photos)

13. `domain/ids.ml`, `plant.ml`, `observation.ml`, `photo.ml`, `tag.ml`, `reference.ml`: records + yojson codecs; round-trip tests in `test/domain`. Done: codecs tested natively.
14. `bindings/cap_sqlite.ml`, `cap_filesystem.ml`, `cap_preferences.ml`, `cap_app.ml` (Jv, `.mli`, `result` at the boundary). Depends: M0.4. Done: a db opened and a file written/read on the phone (spike 2, part 1).
15. `store/db.ml`, `store/schema.ml` (migration 1: architecture §2 tables + `outbox`, `sync_state`, `settings`; `user_version`). Done: fresh install and upgrade from an empty db both reach version 1.
16. `store/plants.ml`, `observations.ml`, `tags.ml`, `photos.ml` (rows only), `settings.ml`, `search.ml` (FTS5 `unicode61 remove_diacritics 2` over names, aliases, tags, place labels). Done: "digitale" finds "Digitale pourpre" and "Digitalis" (spike 2, part 2).
17. `store/outbox.ml`: every write goes through one function that inserts the row and its outbox entry in a single transaction. Done: outbox grows with edits; nothing consumes it yet.
18. `domain/places.ml`: Haversine, 500 m clustering, day-place rule of 4c. Done: native tests on a fixture set.
19. `ui/app.ml` (save orchestration, local only for now); `main.ml` opens the db and mounts the router. Done: app starts on an empty db.
20. Screens from the store: 4a (fixtures replaced), 4n empty state, 4c journal grouped by day with year/À identifier/tag filters, 4l tags, 5d manage tags (rename, merge, delete). Done: tags created, Collection and Journal filtered by them, offline.
21. 4f/4g `screens/species.ml`: hero (placeholder), tags, observations list, notes edited in place, reference block reduced to the 4g text; 5a `edit_plant.ml`: name, aliases, tags, delete with confirmation. Done: a plant is created, edited, deleted; observations cascade as the handoff says.
22. 4h `screens/observation.ml` (date, note, delete; place card as text, map later); 4i/4k/5c `screens/resolve.ml` collection modes only: search my collection, link/relink an observation, free name, "Remettre À identifier", keep/delete dialog. Done: an "À identifier" observation from Journal is linked to an existing or free-name plant.
23. 4m `settings.ml` skeleton: switches and storage radio persisted in `settings`, other rows static. Done: a setting survives a restart.

## M3 — Photos (runnable: field workflow 4d → 4e → 4f with local previews)

24. `bindings/exifr.ml`, `cap_camera.ml`, `cap_geolocation.ml`; `photos/exif.ml` (date, GPS read before any canvas work). Done: EXIF of a phone photo read from OCaml; the mapping part tested on a fixture.
25. `photos/preview.ml`: `createImageBitmap` → ≤1600 px canvas → JPEG q0.7 → `previews/<id>.jpg` via `store/files.ml`; sha256; `store/photos.ml` insert PENDING. Done: a 300 KB preview written and read back as a blob URL (spike 2, part 3), no EXIF left in it.
26. `photos/capture.ml`: `getUserMedia` viewfinder + `cap_camera` gallery pick. Done: the shutter produces a preview file.
27. 4d `screens/record.ml`: dark modal, thumbnail row, optional name with suggestions (collection first, then "Vues ici" from `places`, local only), GPS pill, save without network; 4e `saved.ml`. Done: an observation with two photos saved offline in under 2 s, GPS never blocking.
28. `widgets/photo_grid.ml`, striped loading state, badges (`↑`, local); 4f hero pager (`scroll-snap`) and "Mes photos" grid; cover row in 5a; 4h mosaic and "+". Done: cover photos appear on 4a cards.
29. 5e `screens/viewer.ml` + `widgets/viewer_zoom.ml` (imperative pinch, `scroll-snap` swipe): set as cover, move to another observation, remove (unlink only). Done: all 5e actions work; "Ouvrir dans Google Drive" hidden until M7.

## M4 — References and link interception (spikes 1 and 5; runnable: linked species page)

30. `domain/link.ml`: URL or text containing one → gbif key | plantnet name | wikipedia title | inpn cd_nom | tela nn | powo | inat | free text. Done: one native test per host pattern of architecture §7.
31. `refs/http.ml`: fetch with `User-Agent: Herbier/<version>` (`domain/version.ml` from a dune rule), rate-limited queue (one per source, ≤3 overall), timeouts. Done: ten queued calls to two sources respect the limits (log).
32. `refs/sources/gbif.ml` (species, match, suggest, vernacular search, vernacularNames, distributions, occurrence count, Pl@ntNet media), `wikidata.ml`, `wikipedia.ml`; recorded payloads in `test/fixtures/`. Done: each parser tested against fixtures.
33. `domain/projection.ml` (reference rows → 4f snapshot fields), `store/references.ml` one row per source. Done: projection of two species from fixtures; the count of empty fields is recorded in this doc (spike 5).
34. `refs/pipeline.ml` fan-out per gbif_key, `refs/resolver.ml` (`Domain.Link` + lookups → gbif_key + partial snapshot), wired in `ui/app.ml`: fetch at link time, on ↻, on open when > 90 days. Done: linking fills 4f's reference block; a failing source leaves the others intact.
35. 4f reference block complete: names, type, origin, `widgets/month_grid.ml`, habitat chips, toxicity, organ photos into `refthumbs/`, links row; rows without data disappear. Done: renders for the two spike species, offline after the first fetch.
36. 4i reference search (`species/suggest` + vernacular, 300 ms debounce, offline state); 4k/5c reference "+" path; 5a "Changer" and "Liens de référence" (paste link → `PlantRef`). Done: a free-name plant gets linked and its name becomes an alias.
37. `refs/regional.ml` + `sources/tela.ml`, `inpn.ml` behind a setting; "En France" row. Done: rows appear only when the layer is on and data exists.
38. `AndroidManifest.xml` intent-filters (VIEW/BROWSABLE hosts of §7, SEND text/plain), `bindings/cap_share_target.ml`, `cap_app.ml` `appUrlOpen`; 4j sheet mode of `resolve.ml` with "Première observation ici", "Enlever", recent tags, "Déjà dans ma collection" variant. Done: a Pl@ntNet share and a gbif.org link (after "Ouvrir par défaut") both land on 4j and add the plant (spike 1, part 2); what Pl@ntNet actually shares gets written down here.

## M5 — Map and places (spike 3; runnable: 4b, 5b, mini-map)

39. `web/js/map.js` facade (create, setStyle, setData, click/moveend, getCenter, flyTo, metric circle), `bindings/maplibre.ml`, `geo/map.ml`, `geo/style.ml`, `web/map/positron.json`. Done: OpenFreeMap positron shows the store's observations in the WebView (spike 3, part 1).
40. 4b `screens/map_tab.ml`: `places` pre-clustering + MapLibre clustering, point styles (ink / moss selected / ochre unidentified), filters, floating search, `my_location`, sheet with the place's observations and "Renommer" writing `place_label` on the cluster, tab bar inside the sheet. Done: tapping a cluster lists its observations; a rename persists.
41. 4h mini-map with accuracy circle; 4c "◎" opens 4b centred. Done: both navigations work.
42. `geo/geocode.ml` (Photon forward and reverse, Géoplateforme in France); `place_derived` filled once per observation when online, wired in `ui/app.ml`. Done: a 4c day header shows "Près de …" for an unlabelled observation.
43. 5b `screens/move_point.ml`: fixed centre pin, origin ghost, "déplacé de N m", "Chercher un lieu", validate/reset. Done: moved point stored, accuracy cleared.
44. `bindings/pmtiles.ml`, `geo/tiles.ml` (region download to `tiles/`, `scripts/pmtiles-extract.sh`), `web/map/offline.json`, automatic style switch on connectivity, 4m "Données hors-ligne" row. Done: airplane mode still renders the region (spike 3, part 2). **Fallback** if filesystem-backed PMTiles fails: `addProtocol` write-through cache of visited tiles.

## M6 — Sync and backup (spike 4; runnable: two installs converge)

45. `supabase/config.toml`, `schemas/` (architecture §4 tables, `policies.sql` owner-only RLS, `triggers.sql` moddatetime + loc, `rpc.sql` plants_near), generated migration, `seed.sql`, pgTAP in `supabase/tests/`, `ci.yml` runs `supabase test db`. Done: tests green locally and in CI; anon reads nothing.
46. `bindings/cap_social_login.ml`, `sync/auth.ml`: Credential Manager id token → `signInWithIdToken`, session in Preferences, auto-refresh on resume/background. Done: sign-in from 4m with an "In production" OAuth client and no verification prompt (spike 4, part 1).
47. `sync/postgrest.ml` (upsert, select-since, JWT, paused-project detection), `domain/merge.ml` (LWW on `updated_at`, outbox wins), native tests for merge and outbox ordering. Done: the style guide §12.2 merge cases are tested.
48. `sync/push.ml`, `pull.ml`, `engine.ml` (start, resume, after write, backoff, park 4xx with `last_error`), `store/sync_state.ml`, wired in `ui/app.ml`. Done: an edit on install A shows on install B after pull; parked rows listed in 4m.
49. `sync/previews_mirror.ml` (optional Storage bucket, up and on-demand down); offline banner and "N en attente" from `state.ml`. Done: a fresh install fetches previews on demand.
50. Separate repo `herbier-backups`: `backup.yml` cron running `supabase db dump` twice a week. Done: two dumps committed; project not paused after eight days.

## M7 — Drive originals (spikes 1 and 4; runnable: originals in Drive)

51. `sync/auth.ml` extension: `AuthorizationClient` `drive.file`, 1-hour token on demand; `photos/drive.ml` (folders `Herbier/<species>/`, multipart `files.create` with `appProperties`, `files.get?fields=trashed`). Done: a file lands in the right folder from OCaml (spike 4, part 2).
52. `bindings/cap_uploader.ml`, `photos/upload_queue.ml` (temp original, enqueue, Wi-Fi-only constraint, per-job token callback, PENDING → UPLOADED/FAILED, temp cleanup). Done: an upload completes with the app swiped away and respects Wi-Fi only (spike 1, part 3). **Fallback**: foreground upload with retries.
53. `photos/health.ml` weekly `trashed` check → ORIGINAL_MISSING; 5e "Ouvrir dans Google Drive ↗" and "original introuvable"; 4e Drive card; 4m account card, "File d'envoi", "Envoyer maintenant", storage radio effective. Done: every Drive-related row of 4e/4m/5e is live.

## M8 — Polish and release (runnable: signed release APK)

54. View Transitions (modal from bottom 300 ms, shared hero 4a → 4f 350 ms, fade fallback), pressed states, `screens.css` pass per handoff id. Done: side-by-side check against `Herbier v2.dc.html` for every screen.
55. Empty and error states: 4n illustration in `web/img/`, offline texts on 4g/4i, "serveur en pause" in 4m, "Libérer" (refthumbs eviction, size counters). Done: each state reachable by toggling network or data.
56. `scripts/release.sh`, signing config, `android.yml` release on tag; launcher icons, splash, `strings.xml`. Done: the release APK installed over the debug one keeps the database.

## Screen → milestone

| Screen | Functional | Completed later by |
|---|---|---|
| 4a Collection | M2 (static in M1) | M3 cover photos, M8 transition |
| 4b Carte | M5 | M5.44 offline tiles |
| 4c Journal | M2 | M5 day place from geocoding |
| 4d Noter | M3 | — |
| 4e Enregistré | M3 | M7 Drive card |
| 4f Fiche espèce | M2 (my data) | M3 photos, M4 reference block |
| 4g Fiche sans référence | M2 | M4 "Lier" |
| 4h Observation | M2 | M3 mosaic, M5 mini-map |
| 4i Chercher | M2 (collection) | M4 GBIF search, paste link |
| 4j Lien intercepté | M4 | — |
| 4k À identifier → lier | M2 (collection) | M4 reference "+" |
| 4l Tags | M2 | M3 cover photos |
| 4m Réglages | M2 (switches) | M5 offline data, M6 account, M7 upload queue, M8 pause/free |
| 4n Premier lancement | M2 | M8 illustration |
| 5a Modifier la fiche | M2 | M3 cover row, M4 reference links |
| 5b Déplacer le point | M5 | — |
| 5c Changer d'espèce | M2 (collection) | M4 reference "+" |
| 5d Gérer les tags | M2 | — |
| 5e Visionneuse | M3 | M7 open in Drive |
| 5f Lisibilité | M1 (tokens) | — |

## Ordering and a first usable version

- Fixed order: M0 → M1 → M2 → M3. Everything after depends only on M2 (M7 also on M3) and can be reordered.
- First usable version = M0–M3 plus M6: records plants and photos offline, mirrored to Supabase, without references, map or Drive.
- M4 and M5 are independent: M4 first if links are the main entry path, M5 first if field use is.
- Droppable for v1: 44 (offline tiles), 37 (regional layer), 49 (previews mirror), 53 (health check), the VIEW filters of 38 (keep the SEND share path).

## Risk points

- R1 (M1.12): the glue fails its exit criterion → ocaml-vdom rewrite of 4a and `router.ml`; M2 onwards unaffected.
- R2 (M2.14): `@capacitor-community/sqlite` is awkward from Jv (promise-heavy, transactions) → thin JS helper in `vendor.js`.
- R3 (M3.26): `getUserMedia` in the WebView lacks resolution or torch control → `camera-preview` plugin, 4d layout unchanged.
- R4 (M4.38): Pl@ntNet shares something the classifier cannot resolve → 4j falls back to 4i prefilled with the text.
- R5 (M4.33): the spike shows most 4f fields empty outside France → shrink the reference block rather than add sources.
- R6 (M5.44): filesystem-backed PMTiles fails → visited-tiles cache; offline map becomes "areas already seen".
- R7 (M6.46): the OAuth client cannot be "In production" without verification → email+password for Supabase, Drive deferred.
- R8 (M7.52): uploader network constraints do not work → foreground upload; "Envoyer seulement en Wi-Fi" becomes a manual check.
- R9 (any): Capacitor WebView regressions → same bundle in a TWA; `bindings/` stays the only Capacitor-aware layer.

## Decisions to make

1. **M1 data source.** (a) fixtures in `test/fixtures/`, real store in M2; (b) build `store/` first and spike 4a on real rows; (c) fixtures behind an in-memory module with the M2 store signature. Recommend (a): the spike judges the glue, not SQLite.
2. **Sync before or after photos.** (a) M3 photos then M6 sync, as written; (b) M6 right after M2 so records are mirrored before photos exist; (c) M6 after M4. Recommend (a): photos are the field workflow, text rows can wait a few weeks.
3. **Offline map region in v1.** (a) yes, step 44 in M5; (b) v2, online tiles only; (c) visited-tiles cache only. Recommend (b) unless field use without coverage is frequent.
4. **Link interception in v1.** (a) VIEW intent-filters and SEND share target; (b) SEND share target only; (c) neither, paste in 4i. Recommend (b): no "Ouvrir par défaut" step and it covers Pl@ntNet.
5. **Test strategy per milestone.** (a) native alcotest for `domain/` only, manual device runs for the rest; (b) `test/js/` with jsdom for `rb.ml` from M1; (c) (a), adding jsdom only if M1.12 fails. Recommend (c).
6. **Package management for M0.** (a) `dune pkg lock`; (b) opam switch + lock file; (c) opam locally, dune pkg in CI. Recommend (a) as in layout.md; fall back to (b) if a dependency has no dune-pkg-compatible release.
7. **Reference fetch timing.** (a) eager at link time, in the background; (b) lazy on first open of 4f; (c) eager for GBIF/Wikidata, lazy for the regional layer. Recommend (a): 4j promises "complet en arrière-plan" and offline 4f then works.
8. **First device build.** (a) debug-signed sideload from `android.yml` artifacts; (b) release-signed from day one; (c) Play internal track. Recommend (a) until M8.
9. **Regional layer in v1.** (a) Tela + INPN wired in step 37 behind a setting; (b) skip until a region is fixed. Recommend (b) unless the plants are mostly in France (stack.md open decision 1).
10. **Camera path.** (a) `getUserMedia` viewfinder as designed; (b) system camera via `@capacitor/camera` only, 4d reduced to thumbnails + name; (c) `camera-preview` plugin. Recommend (a), (c) as the R3 fallback.
11. **Google Photos radio in 4m.** (a) shown as "bientôt", disabled; (b) removed. Recommend (b): no dead rows (stack.md open decision 3).
