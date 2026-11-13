# Herbier — Implementation plan

Status: decided, 2026-09-16 (see Decisions at the end). Orders the work
needed to reach the mockup (`design_handoff_herbier/README.md`, screens
4a–4n and 5a–5f) with the modules of `layout.md`, the decisions of
`stack.md` and the design of `architecture.md`. The six spikes of
architecture §10 are absorbed as the first steps of the milestone that
needs them: spike 1 (shell) → M0.4, M4.39, M7.52; spike 2 (storage) →
M1.10, M1.12, M3.27; spike 3 (map) → M5.40 (its offline half is v2);
spike 4 (auth) → M6.46, M7.51; spike 5 (references) → M4.35; spike 6 (UI)
→ M2.

Conventions: one step = what gets written · what it depends on · done when.
Screen ids refer to the handoff; a screen is "functional" when it renders
from the local store and every action on it that does not need a later
milestone works. Each milestone ends in something runnable in a browser
(`dune build @web` + a static server) or on the phone (`scripts/dev.sh`).

## M0 — Toolchain (runnable: hello page in browser and on phone)

1. `dune-project` (two packages: `herbier`: js_of_ocaml, brr, react, reactiveData, yojson, ptime, uuidm, alcotest; `postgrest`: yojson, alcotest), `dune pkg lock` with `dune.lock/` committed, `.ocamlformat` (0.29.0). Done: `dune build` from a clean clone with only dune installed.
2. `app/dune`, `app/main.ml` (`(modes js)`), `app/domain/dune` also built natively, `test/domain/` with one alcotest. Done: `dune test` passes; layout §2 dependency direction is in the `libraries` fields.
3. `web/index.html`, `web/dune` (`@web` alias → `_build/default/web/dist`, Capacitor's `webDir` pointed at it), `package.json` with esbuild and sass, empty `web/js/vendor.js` bundle, `web/sass/app.sass` (indented syntax) compiled to `dist/app.css`. Done: serving `dist/` shows a "Herbier" heading written by Brr and styled by `app.css`.
4. `npx cap init` + `npx cap add android`, `capacitor.config.ts` with `webDir` = `_build/default/web/dist`, `android/` committed, `scripts/dev.sh`. Done: the same page on the phone through `cap run android -l` (spike 1, part 1).
5. `.github/workflows/ci.yml` (build, test, `fmt --check`) and `android.yml` (debug APK artifact, the device build until M8). Done: green run on `main`; APK downloadable and sideloadable.

## M1 — Local store (spike 2; runnable: seeded db queried from a plain debug page on the phone)

6. `domain/ids.ml`, `plant.ml`, `observation.ml`, `photo.ml`, `tag.ml`, `reference.ml`: records and typed ids, no row codecs (rows go through `Postgrest` column types; ids and value sets carry the `to_json` / `of_json` column codecs). Done: builds natively and under jsoo; `test/domain` covers ids.
7. `domain/places.ml`: Haversine, 500 m clustering, day-place rule of 4c. Done: native tests on a hand-written point set.
8. `lib/postgrest/` core, written now because the store decodes rows with it: `ty` GADT, `('table, 'a) col`, applicative `row` (`let+`/`and+`), `filter`, `request`, `select`/`upsert`/`delete`; `test/postgrest/`. Done: each request kind renders to the expected path, query string, headers and body; a recorded response decodes through a `Row` spec; `is_null` on a non-nullable column is rejected by the compiler.
9. `supabase/config.toml`, first hand-written migration (architecture §4 tables), `seed.sql`, first `schema-dump.py` run committed; `supabase/schema/catalog.json` (the output of `lib/postgrest/codegen/catalog.sql`, one JSON object per table, written by `scripts/catalog-dump.sh`) committed; `app/store/tables.ml` (`Postgrest` columns of the synced tables) generated from it by `postgrest-codegen` (`lib/postgrest/codegen/`: types from the Postgres types, ids and lookup codecs from `metadata:` comments, relationships from foreign keys; no SQL parsing), a dune diff rule in `app/store/dune` checking it in `dune test`. Depends: local stack (Docker) for the dumps. Done: `dune test` passes locally and in CI and fails when a column is renamed in the catalog without regenerating; CI checks both dumps are fresh.
10. `bindings/cap_sqlite.ml`, `cap_filesystem.ml`, `cap_preferences.ml`, `cap_app.ml` (Jv, `.mli`, `result` at the boundary). Depends: M0.4. Done: a db opened and a file written/read on the phone (spike 2, part 1).
11. `store/db.ml` (open, exec, bind params over `cap_sqlite`, the plugin's JSON rows decoded with `Postgrest.Row`), `store/schema.ml` (migration 1: architecture §2 tables + `outbox`, `sync_state`, `settings`; `user_version`). Done: fresh install and upgrade from an empty db both reach version 1; a `Tables.plants` row round-trips through the plugin.
12. `store/plants.ml`, `observations.ml`, `tags.ml` (`plant_tags` ids derived from the natural key, architecture §4), `photos.ml` (rows only), `settings.ml`, `search.ml` (FTS5 `unicode61 remove_diacritics 2` over names, aliases, tags, place labels); a dev seed (a dozen plants, observations, tags) behind a debug flag for M2. Done: "digitale" finds "Digitale pourpre" and "Digitalis" (spike 2, part 2).
13. `store/outbox.ml`: every write goes through one function that inserts the row and its outbox entry in a single transaction; adds explicit begin/commit/rollback to `bindings/cap_sqlite.ml` (the plugin's per-call transaction is off inside them). Done: outbox grows with edits; nothing consumes it yet.

Possible upgrade, not a decision: sqlgg (SQL-guided generator) could give typed hand-written SQL for the store by inferring types from the CREATE TABLE statements, if its async traits can be implemented over the Capacitor plugin; a half-day spike, see `docs/exploratory_research/sqlgg-jsoo.md` (report pending).

## M2 — UI foundation and record screens (spike 6; runnable: offline app with records, no photos)

14. `ui/rb.ml` + `.mli` per primer §6: `text`, `attr`, `class_`, `style`, `children`, `rlist`, `ev`, `release`. Depends: M0. Done: a toy page with a counter, a class toggle and an `RList` of rows; `release` stops updates.
15. `web/sass/_tokens.sass` (custom properties, the only token source), `_base.sass` (`@font-face`, type scale, 5f rules), `ui/theme.ml` (reads the properties OCaml needs with `getComputedStyle` once at startup), `fonts/` (Manrope, Newsreader, `scripts/subset-icons.sh`). Done: a dev route shows every colour and type role of the handoff; `Theme` returns the map colours the CSS declares.
16. `ui/widgets/` chip, card, list_row, tab_bar, icon, text_field; `_widgets.sass` with its mixins. Done: each widget has a fixture entry on a dev "gallery" route.
17. `ui/router.ml` (route variant, `S.map ~eq:( == )` over the route building the current screen, `S.diff` releasing the previous one, holding the current screen's binding list until its release (js_of_ocaml 6 weak arrays are `WeakRef`s, so an unreferenced binding silently stops), release of the previous screen; takes over all the `#dev/*` fragments (`dev/storage`, `dev/store`, `dev/seed`, `dev/refs-http`, `dev/photos`, `dev/rb`, `dev/theme`, `dev/gallery`) from `main.ml`, compiled into dev builds only, so a release APK cannot seed or probe the real database) and `ui/state.ml` (filters, network, account). Done: switching tabs tears the old screen down; binding count back to baseline.
18. `screens/collection.ml` (4a) over `Store.Plants` and `Store.Search` on the M1 seed: title + counter, search filtering an `RList`, tag chips, 2-column grid; `sass/screens/collection.sass`. Done: search and chip filter patch the grid (only touched cards re-rendered).
19. `widgets/sheet.ml`: bottom sheet whose drag is a `float` signal bound to `transform`, snap points. Done: 60 fps drag on the phone; no retained memory growth during a drag and no garbage-collection pause that drops a frame (short-lived allocation per move is accepted: each move runs a react update step; optimise only if the drag is slow on the phone).
20. Spike exit criterion: enter/leave 4a fifty times; no stale updates, JS heap flat (CDP, after a forced GC: the WebView's `performance.memory` is bucketed), no dropped frames on the sheet. **Fallback trigger**: either check still fails after one day of fixing, or `rb.ml` needs more than ~300 lines to stay correct → redo 4a in ocaml-vdom, compare, update `stack.md` either way.
21. `ui/app.ml` (save orchestration, local only for now); `main.ml` opens the db and mounts the router. Done: app starts on an empty db; the spike's enter/leave is rerun through the router (`#collection` ↔ `#journal` fifty times with `scripts/webview.mjs`, `herbierDev.live()` back to its baseline).
22. Screens from the store: 4n empty state, 4c journal grouped by day with year/À identifier/tag filters, 4l tags, 5d manage tags (rename, merge, delete). Done: tags (seeded until 23) renamed, merged and deleted, Collection and Journal filtered by them, offline.
23. 4f/4g `screens/species.ml`: hero (placeholder), tags, observations list, notes edited in place, reference block reduced to the 4g text; 5a `edit_plant.ml`: name, aliases, tags, delete with confirmation. Done: a plant is created, edited, deleted; a tag is created from the fiche (« + tag »); observations cascade as the handoff says.
24. 4h `screens/observation.ml` (date, note, delete; place card as text, map later); 4k/5c `screens/resolve.ml` collection modes only: search my collection, link/relink an observation, free name, "Remettre À identifier", keep/delete dialog. Done: an "À identifier" observation from Journal is linked to an existing or free-name plant.
25. 4m `settings.ml` skeleton: switches and the storage radio (Drive / app only; no Google Photos row) persisted in `settings`, other rows static. Done: a setting survives a restart.

## M3 — Photos (runnable: field workflow 4d → 4e → 4f with local previews)

26. `bindings/exifr.ml`, `cap_camera.ml`, `cap_geolocation.ml`; `photos/exif.ml` (date, GPS read before any canvas work). Done: EXIF of a phone photo read from OCaml; the mapping part tested on a fixture.
27. `photos/preview.ml`: `createImageBitmap` → ≤1600 px canvas → JPEG q0.7 → `previews/<id>.jpg` via `store/files.ml`; sha256 of the original as captured (architecture §2, §5); `store/photos.ml` insert `pending`. Done: a 300 KB preview written and read back as a blob URL (spike 2, part 3), no EXIF left in it.
28. `photos/capture.ml`: `getUserMedia` viewfinder + `cap_camera` gallery pick. Done: the shutter produces a preview file.
29. 4d `screens/record.ml`: dark modal, thumbnail row, optional name with suggestions (collection first, then "Vues ici" from `places`, local only), GPS pill, save without network; 4e `saved.ml`. Done: an observation with two photos saved offline in under 2 s, GPS never blocking.
30. `widgets/photo_grid.ml`, striped loading state, badges (`↑`, local); 4f hero pager (`scroll-snap`) and "Mes photos" grid; cover row in 5a; 4h mosaic and "+". Done: cover photos appear on 4a cards.
31. 5e `screens/viewer.ml` + `widgets/viewer_zoom.ml` (imperative pinch, `scroll-snap` swipe): set as cover, move to another observation, remove (unlink only). Done: all 5e actions work; "Ouvrir dans Google Drive" hidden until M7.

## M4 — References and link interception (spikes 1 and 5; runnable: linked species page)

32. `domain/link.ml`: URL or text containing one → gbif key | plantnet name | plantuse name (host to verify) | wikipedia title | inpn cd_nom | tela nn | powo | inat | free text. Done: one native test per host pattern of architecture §7.
33. `refs_io/http.ml`: fetch identified as `Herbier/<version>` (`domain/version.ml` from a dune rule; `Api-User-Agent` to Wikimedia, since the WebView drops a page-set `User-Agent`), rate-limited queue (one per source, ≤3 overall), timeouts. Done: ten queued calls to two sources respect the limits (log).
34. `refs/sources/gbif.ml` (species, match, suggest, vernacular search, vernacularNames, distributions, occurrence count, Pl@ntNet media), `wikidata.ml`, `wikipedia.ml`: request descriptions and payload decoders; recorded payloads in `test/fixtures/`. Done: each decoder tested natively against fixtures.
35. `refs/projection.ml` (reference rows → 4f snapshot fields), `store/references.ml` one row per source (`reference` and `plant_refs` ids derived from `(plant_id, source)`, architecture §4). Done: projection of two species from fixtures; the count of empty fields is recorded in this doc (spike 5). Measured (M4.35, fixtures of 2026-11): of the 14 snapshot fields (altitude dropped), 7 are empty for Digitalis purpurea and 7 for Arnica montana: the six of the regional layer (life form, French status, protection, flowering months, habitat, ecology) for both, plus the global red list (Digitalis: no global IUCN assessment) or toxicity (Arnica: not in the fr summary).
36. `refs_io/pipeline.ml` fan-out per gbif_key, `refs_io/resolver.ml` (`Domain.Link` + lookups → gbif_key + partial snapshot), wired in `ui/app.ml`: fetch eagerly at link time in the background, on ↻, on open when > 90 days. Done: linking fills 4f's reference block; a failing source leaves the others intact.
37. 4f reference block complete: names, type, origin, `widgets/month_grid.ml`, habitat chips, toxicity, organ photos into `refthumbs/` (with the local `ref_images` table, a store migration), links row; rows without data disappear. Done: renders for the two spike species, offline after the first fetch.
38. 4i as a mode of `resolve.ml`, entered from 4j's « Chercher »: my collection (« Ouvrir › ») and reference search (`species/suggest` + vernacular, 300 ms debounce, offline state); 4k/5c reference "+" path; 5a "Changer" and "Liens de référence" (paste link → `PlantRef`). Done: a free-name plant gets linked and its name becomes an alias.
39. `AndroidManifest.xml` intent-filters, Pl@ntNet only (user decision 2026-11-12): VIEW/BROWSABLE for `identify.plantnet.org` and the Pl@ntUse hosts of §7, SEND text/plain (Pl@ntNet's share); other hosts (gbif.org, Wikipedia, POWO, INPN, Tela Botanica, iNaturalist) are not intercepted and are recognised only when pasted in « Liens de référence » (M4.38). `bindings/cap_share_target.ml`, `cap_app.ml` `appUrlOpen`; 4j sheet mode of `resolve.ml` with "Première observation ici", "Enlever", recent tags, "Déjà dans ma collection" variant. Done: a Pl@ntNet share and a Pl@ntUse link (after "Ouvrir par défaut") land on 4j and add the plant (spike 1, part 2); a gbif.org link opens the browser; what Pl@ntNet actually shares and the real Pl@ntUse host get written down here. Found (M4.39): Pl@ntUse is `plantuse.plantnet.org` (`uses.plantnet-project.org` redirects there with a 301, `uses.plantnet.org` does not resolve; curl, 2026-11-12); a link or share that cold-starts the app is delivered by the plugins' retained events (`appUrlOpen`, `shareReceived`), so `getLaunchUrl` is not used; what the Pl@ntNet app puts in a share (URL alone, text and URL, or a name; `#dev/link` « Dernier lien reçu ») is pending the phone run.
59. Regional layer on 4f (France-focused, works elsewhere; user decision 2026-11-12): `refs/sources/inpn.ml` (TaxRef status, protection, French red list, presence in France) and `refs/sources/tela.ml` (flowering months, habitat, ecology), request descriptions and payload decoders with recorded fixtures, fetched by `refs_io/pipeline.ml` only for species that have a TaxRef id (Wikidata P3186, else Tela's `bdtfx/noms?masque=` bridge), projected into the existing 4f rows. Rows show only when the data exists, so a species outside France keeps the global block of M4.37 unchanged. Pasted INPN/Tela links still resolve through Wikidata (M4.36); these sources are enrichment, not link hosts. Done: Digitalis purpurea and Arnica montana show « En France », protection, French red list, Floraison and Habitat from fixtures; a species without a TaxRef id fetches nothing from INPN/Tela and renders as before; each decoder tested natively.

## M5 — Map and places (spike 3; runnable: 4b, 5b, mini-map)

40. `web/js/map.js` facade (create, setStyle, setData, click/moveend, getCenter, flyTo, fitBounds, renderedIds), `bindings/maplibre.ml`, `geo/map.ml`, `geo/style.ml`, `geo/features.ml` (observation points; the metric circle as a polygon computed in OCaml), `web/map/positron.json`; point colours from `ui/theme.ml`. Done: OpenFreeMap positron shows the store's observations in the WebView (spike 3, online half).
41. 4b `screens/map_tab.ml`: `places` pre-clustering + MapLibre clustering, point styles (ink / moss selected / ochre unidentified), filters, floating search, `my_location`, sheet with the place's observations and "Renommer" writing `place_label` on the cluster, tab bar inside the sheet. Done: tapping a cluster lists its observations; a rename persists.
42. 4h mini-map with accuracy circle; 4c "◎" opens 4b centred. Done: both navigations work.
43. `geo/geocode.ml` (Photon forward and reverse, Géoplateforme in France); `place_derived` filled once per observation when online, wired in `ui/app.ml`. Done: a 4c day header shows "Près de …" for an unlabelled observation.
44. 5b `screens/move_point.ml`: fixed centre pin, origin ghost, "déplacé de N m", "Chercher un lieu", validate/reset. Done: moved point stored, accuracy cleared.
57. Location privacy: place names never leave the phone unless chosen. `geo/place_name.ml` resolves a point by asking, in order, (1) the user's own labelled places (a `place_label` within 500 m), then (2) each enabled source among « IGN hors-ligne » (M5.58), « IGN en ligne » (Géoplateforme) and « Photon en ligne », else « Lieu inconnu »; `geocode.ml` and `ui/app.ml` call nothing remote unless its source is enabled. 4m gets a « Noms de lieux » section: one switch per source, all off by default, persisted in `settings`. First opening shows a one-time dialog explaining that positions stay on the phone and that each source can be turned on (and what it sends, to whom). Done: with every source off, an unlabelled observation shows « Lieu inconnu » and no request leaves the phone (log); with « Photon en ligne » on, M5.43's behaviour returns; a labelled place within 500 m names a new observation offline.
58. « IGN hors-ligne »: download IGN commune boundaries (Admin Express COG carto, Etalab 2.0) per département, chosen in 4m, from the Géoplateforme WFS, simplified and stored locally (`store/files.ml`, a `commune_packs` table, sizes shown, « Supprimer »), and `geo/communes.ml`: point-in-polygon lookup giving « Près de <commune> ». Done: after downloading one département, an observation in it is named offline (airplane mode); outside it, the next source or « Lieu inconnu »; the pack's size is recorded in this doc. Pack sizes (2026-11-12, stored file after 20 m simplification; WFS download raw / gzip): 90 Territoire de Belfort 89 ko (101 communes, 5.6 k points; 299 ko / 99 ko), 68 Haut-Rhin 392 ko (366 communes; 1.27 Mo / 439 ko), 62 Pas-de-Calais, the largest, 961 ko (887 communes, 61 k points; 2.84 Mo / 994 ko).

## M6 — Sync and backup (spike 4; runnable: two installs converge)

45. pgTAP in `supabase/tests/` over the M1.9 schema (owner-only RLS policies, `updated_at` + loc triggers, `plants_near` RPC, all written in M1.9's migration), replacing `supabase/scripts/smoke.sql`; any later schema change as a new hand-written migration, re-dumped with `supabase/scripts/schema-dump.py` and `scripts/catalog-dump.sh` and committed together; `ci.yml` runs `supabase test db` next to `schema-dump.py --check`. Done: tests green locally and in CI; anon reads nothing; the dump is fresh.
46. `bindings/cap_social_login.ml`, `sync/auth.ml`: Credential Manager id token → `signInWithIdToken`, session in Preferences, auto-refresh on resume/background. Sign-ups are off (`config.toml`), so the account is created by hand (dashboard or admin API) before its first sign-in, locally too. Done: sign-in from 4m with an "In production" OAuth client and no verification prompt (spike 4, part 1).
47. `sync/net/transport.ml` (a `Postgrest.Client.HTTP` over Brr fetch, body to the decoder; JWT, paused-project detection), the push upsert and pull select-since requests over `Tables`, `domain/merge.ml` (LWW in the server's `updated_at` order, the device's `updated_at` never compared; outbox wins; `reference.payload` compared structurally through Yojson, never as text, since `jsonb` reorders keys); native tests for the rendered requests, merge and outbox ordering. Done: the upsert and select-since render to the expected PostgREST requests in `test/sync/`; the style guide §12.2 merge cases are tested.
48. `sync/push.ml`, `pull.ml`, `engine.ml` (start, resume, after write, backoff, park 4xx with `last_error`), `store/sync_state.ml`, wired in `ui/app.ml`. Pull gets its own transaction entry point (`defer_foreign_keys`), and `Outbox.without_entry` / `Tags.upsert_plant_tag` stop being callable from `Db.write`. Done: an edit on install A shows on install B after pull; parked rows listed in 4m.
49. ~~`sync/previews_mirror.ml` (optional Storage bucket, up and on-demand down)~~ Dropped (user decision 2026-11-12): previews can be rebuilt from the originals, so no Storage bucket. The offline banner and "N en attente" from `state.ml` move to M8.55 (empty and error states).
50. Keep-alive from the phone: a background job (`@capacitor/background-runner`, WorkManager underneath) runs a light sync about twice a week even when the app is closed: push pending outbox rows, then one authenticated PostgREST query, so the free project sees activity and does not pause. The job script stays small (no OCaml, no WebView) and reads the session the app hands it at each sign-in. No database dumps anywhere: the device is the source of truth and Supabase its copy (user decision 2026-11-12: no personal data on GitHub, no separate backup). Done: with the app closed, the job runs (logged) and its request reaches Supabase; whether an API request counts as activity for the pause is checked in Supabase's docs and recorded here.

## M7 — Drive originals (spikes 1 and 4; runnable: originals in Drive)

51. `sync/auth.ml` extension: `AuthorizationClient` `drive.file`, 1-hour token on demand; `photos/drive.ml` (folders `Herbier/<species>/`, multipart `files.create` with `appProperties`, `files.get?fields=trashed`). Done: a file lands in the right folder from OCaml (spike 4, part 2).
52. `bindings/cap_uploader.ml`, `photos/upload_queue.ml` (temp original, enqueue, Wi-Fi-only constraint, per-job token callback, `pending` → `uploaded`/`failed`, temp cleanup). Done: an upload completes with the app swiped away and respects Wi-Fi only (spike 1, part 3). **Fallback**: foreground upload with retries.
53. `photos/health.ml` weekly `trashed` check → `original_missing`; 5e "Ouvrir dans Google Drive ↗" and "original introuvable"; 4e Drive card; 4m account card, "File d'envoi", "Envoyer maintenant", storage radio effective. Done: every Drive-related row of 4e/4m/5e is live.

## M8 — Polish and release (runnable: signed release APK)

54. View Transitions (modal from bottom 300 ms, shared hero 4a → 4f 350 ms, fade fallback), pressed states, `sass/screens/` pass per handoff id. Done: side-by-side check against `Herbier v2.dc.html` for every screen.
55. Empty and error states: 4n illustration in `web/img/`, offline texts on 4g/4i, offline banner and "N en attente" from `state.ml` (moved from the dropped M6.49), "serveur en pause" in 4m, "Libérer" (refthumbs eviction, size counters). Done: each state reachable by toggling network or data.
56. `scripts/release.sh`, signing config, `android.yml` release on tag; launcher icons, splash, `strings.xml`. Done: the release APK installed over the debug one keeps the database.

## Screen → milestone

| Screen | Functional | Completed later by |
|---|---|---|
| 4a Collection | M2 | M3 cover photos, M8 transition |
| 4b Carte | M5 | v2 offline tiles |
| 4c Journal | M2 | M5 day place from geocoding |
| 4d Noter | M3 | — |
| 4e Enregistré | M3 | M5 « Corriger la position » (5b), M7 Drive card (live upload state) |
| 4f Fiche espèce | M2 (my data) | M3 photos, M4 reference block |
| 4g Fiche sans référence | M2 | M4 "Lier" |
| 4h Observation | M2 | M3 mosaic, M5 mini-map |
| 4i Chercher | M4 (collection and GBIF search; entered from 4j; « + » creates the linked plant directly, not « 4j pré-remplie », decided in M4.39) | paste link |
| 4j Lien intercepté | M4 | M8 modal transition (54); v2 drag-to-close, place name on the card before the save |
| 4k À identifier → lier | M2 (collection) | M4 reference "+" |
| 4l Tags | M2 | M3 cover photos |
| 4m Réglages | M2 (switches) | M5 « Noms de lieux » (M5.57 source switches, M5.58 IGN download), M6 account, M7 upload queue, M8 pause/free; v2 offline data |
| 4n Premier lancement | M2 | M8 illustration |
| 5a Modifier la fiche | M2 | M3 cover row, M4 reference links |
| 5b Déplacer le point | M5 | — |
| 5c Changer d'espèce | M2 (collection) | M4 reference "+" |
| 5d Gérer les tags | M2 | — |
| 5e Visionneuse | M3 | M7 open in Drive |
| 5f Lisibilité | M2 (tokens) | — |

## Ordering and a first usable version

- Fixed order: M0 → M1 → M2 → M3. Everything after depends only on M2 (M7 also on M3) and can be reordered.
- First usable version = M0–M3 plus M6: records plants and photos offline, mirrored to Supabase, without references, map or Drive.
- M4 and M5 are independent: M4 first if links are the main entry path, M5 first if field use is.
- Droppable for v1: 53 (health check). 49 (previews mirror) is dropped (2026-11-12).

## Later (v2)

- Offline map region: `bindings/pmtiles.ml`, `geo/tiles.ml` (region download to `tiles/`, `scripts/pmtiles-extract.sh`), `web/map/offline.json`, automatic style switch on connectivity, 4m "Données hors-ligne" row (spike 3, offline half). If filesystem-backed PMTiles fails: `addProtocol` write-through cache of visited tiles, offline map becomes "areas already seen".

## Risk points

- R1 (M2.20): the glue fails its exit criterion → ocaml-vdom rewrite of 4a and `router.ml`; M1 and M3 onwards unaffected. Bindings, stale updates, heap and the sheet's frames (`#dev/sheet`, 0 dropped over ten drags) pass on the emulator (`stack.md`), pending the sheet's frames on the phone: R1 is closed once that run is recorded in the M2.20 PR.
- R2 (M1.10, M1.13): `@capacitor-community/sqlite` is awkward from Jv (promise-heavy, transactions) → thin JS helper in `vendor.js`. M1.10 bound it from Jv without a helper; M1.13 bound transactions the same way (`beginTransaction` / `commitTransaction` / `rollbackTransaction` and `run`'s `transaction` flag, with `Db` serialising its operations). No helper needed, pending the `#dev/store` outbox group on the device (rollback, write after rollback, overlap): R2 is closed once that run is recorded in the M1.13 PR.
- R3 (M1.11): `Postgrest.Row` does not fit the plugin's row format → hand-written decoders per table; `Postgrest` unchanged for sync. Resolved in M1.11: it fits except for JSON columns (SQLite returns their text), which `Codec.decode ~json` (the query's JSON columns, typed from `Tables`) parses before `Row`.
- R4 (M3.28): `getUserMedia` in the WebView lacks resolution or torch control → `camera-preview` plugin, 4d layout unchanged.
- R5 (M4.39): Pl@ntNet shares something the classifier cannot resolve → 4j falls back to 4i prefilled with the text. Implemented in M4.39: free text, a Pl@ntNet observation link and a link that names no species replace 4j with 4i prefilled with the resolver's query, or with the shared text around the link when that query is empty (a lone link the classifier rejects gives an empty query, not its URL); a failed lookup stays on 4j (« Réessayer », and an offline one resolves when the network returns).
- R6 (M4.35): the spike shows most 4f fields empty outside France → shrink the reference block rather than add sources. Measured in M4.35: 7 of the 14 fields are filled for both spike species; the 7 empty ones are the six Tela/INPN fields plus one global field each, so the block shrinks (rows without data disappear, M4.37) rather than adding sources. Both species are French natives: how the global fields fill for a species outside France is not measured. M4.37: 4f shows Noms, Origine, Toxicité, Photos par organe (fleur, feuille, port) and Liens for Digitalis purpurea, and Noms, Origine, Liste rouge (global IUCN, « LC · préoccupation mineure »), Photos par organe (four organs) and Liens for Arnica montana; Type, Floraison and Habitat have their rows but no source fills them in v1.
- R7 (M6.46): the OAuth client cannot be "In production" without verification → email+password for Supabase, Drive deferred.
- R8 (M7.52): uploader network constraints do not work → foreground upload; "Envoyer seulement en Wi-Fi" becomes a manual check.
- R9 (any): Capacitor WebView regressions → same bundle in a TWA; `bindings/` stays the only Capacitor-aware layer.

## Decisions

Taken 2026-09-16; the toolchain ones are in `layout.md`.

- The local store comes first (M1) and the UI spike (M2) runs on real rows; `test/fixtures/` keeps recorded API payloads only. No throwaway data layer, and the spike exercises the queries it will live on. Addendum 2026-11-10 (M3.26): "recorded API payloads" widens to recorded external payloads (API responses, library output such as exifr's), still never app rows.
- Photos (M3) before sync (M6): photos are the field workflow, text rows can wait.
- Offline map region is v2; v1 uses online tiles only.
- Link interception in v1 = the SEND share target and the VIEW intent-filters, Pl@ntUse host included. Narrowed 2026-11-12: intercepted hosts are Pl@ntNet's only (`identify.plantnet.org`, Pl@ntUse); other reference hosts are recognised only when pasted (gbif.org may be re-added if needed).
- Tests: alcotest natively on `domain/`, `lib/postgrest/`, `refs/`; browser-side tests only if M2.20 fails its leak check.
- Package management: `dune pkg lock` from M0; opam switch with a lock file as the fallback.
- References are fetched eagerly at link time, in the background: 4j promises it and 4f then works offline.
- Device builds are debug-signed sideloads from `android.yml` artifacts until M8.
- ~~Regional (France-only) sources are skipped until the region is decided.~~ Decided 2026-11-12: France-focused, works elsewhere; INPN and Tela Botanica are an optional regional layer (M4.59) whose rows show only when they have data.
- Camera: in-app viewfinder via the browser camera stream; `camera-preview` plugin as the fallback (R4).
- The Google Photos row is removed from 4m; the storage radio offers Drive and app-only.
