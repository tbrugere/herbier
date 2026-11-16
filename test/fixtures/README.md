Recorded payloads only: API responses (`<source>_<endpoint>_<id>.json`, e.g.
`gbif_species_5414995.json`, `wikidata_entity_Q157555.json`,
`wikipedia_summary_fr_Digitalis_purpurea.json`; later `tela_<nn>.json`,
`inpn_<cd_nom>.json`) and exifr output (`exifr_<name>.json`, below). Never app
rows. Each API file is fetched once, committed, and never edited.

`gbif_*`, `wikidata_*`, `wikipedia_*.json`: recorded by
`scripts/record-refs-fixtures.sh` (`[--force]` to re-record), one file per
request. The two reference species are **Digitalis purpurea** (GBIF 5414995,
Q157555) and **Arnica montana** (GBIF 5405976, Q207848, a WCVP-poorer taxon),
plus the edge payloads `Herbier_refs` decoders branch on (a synonym, a FUZZY
and a HIGHERRANK match, a NONE match, an unknown Wikidata id (API error
`no-such-entity`), a Wikipedia disambiguation page). See `test/refs/test_request.ml` for the exact request
each file records.
The fan-out and resolver tests (`test/refs/test_fanout.ml`,
`test_resolve.ml`) add: the accepted taxon of the synonym
(`gbif_species_2889173`), both orders of the candidate search
(`gbif_suggest_digitale_pourpre`, `gbif_vernacular_search_digitalis_purp`), an
empty Pl@ntNet media page (`gbif_plantnet_media_1`), the iNat / TaxRef / Tela
Wikidata searches (`wikidata_search_p3151_*`, `_p3186_*`, `_p3105_*`) and
Arnica's frwiki sitelink summary (`wikipedia_summary_fr_Arnica_des_montagnes`).
`Resolve.chosen`'s synonym pair: `gbif_species_7971454` (Digitalis
purpurascens Lej., SYNONYM, acceptedKey 5708907) and `gbif_species_5708907`
(its accepted taxon, Digitalis purpurea subsp. purpurea).

`photon_*`, `geoplateforme_*.json`: recorded by
`scripts/record-geo-fixtures.sh` (`[--force]` to re-record; it pauses 1.2 s
between fetches, since both APIs answer bursts with empty bodies), one file per
request: Photon reverse and search (`photon_reverse_<point>`,
`photon_search_<query>`) and IGN Géoplateforme reverse
(`geoplateforme_lieu_dit_<point>`, `geoplateforme_commune_<point>`). The points
are the Schlucht pass and a Landes forest (France), Lausanne (inside the coarse
France box, outside France), Kew (outside the box) and a point of the Atlantic
(nothing found). See `test/geo/test_geocode.ml` for the exact request each file
records.

`geoplateforme_wfs_*.json`: « IGN hors-ligne », recorded by
`scripts/record-geo-fixtures.sh` from the Géoplateforme WFS (Admin Express COG
carto): the full département list (`geoplateforme_wfs_departements.json`), the
101 communes of Territoire de Belfort (`geoplateforme_wfs_communes_90.json`,
the smallest metropolitan département with real towns, used for the point
lookups too), and an unknown code's empty answer
(`geoplateforme_wfs_communes_99.json`). See `test/geo/test_communes.ml` for the
exact request each file records. Admin Express COG carto is Etalab 2.0
(Licence Ouverte), attribution required: « Limites communales : IGN, Admin
Express COG carto (Licence Ouverte 2.0) ».

`exifr_<name>.json`: what `Herbier_bindings.Exifr.parse ~pick:Exif.tags`
returns for one photo, never edited:

- `exifr_pil_*`: small JPEGs written by `uv run scripts/exif-fixture-jpegs.py
  <dir>` with the EXIF tags their name says, recorded with
  `node scripts/exifr-fixture.mjs <dir>/<name>.jpg`.
- `exifr_emulator_camera`: a photo of the Android emulator's camera app
  (API 35), pulled with adb and recorded the same way.
- `exifr_picker_pil_offset_gps`: the `#dev/photos` output (Android emulator,
  API 35) for `pil_offset_gps.jpg` picked through the system photo picker: the
  copy keeps the dates but its GPS tags come back emptied.

No real phone photo is recorded yet: a camera photo picked on the phone through
`#dev/photos` belongs next to these as `exifr_phone_<model>.json`, with a test.

`gotrue_<endpoint>_<case>_<status>.json`: GoTrue (Supabase Auth) answers,
recorded against the local stack by `scripts/record-gotrue-fixtures.sh`
(`[--force]` to re-record), read by `test/sync/test_sync.ml`:

- `gotrue_token_refresh_200.json`: a successful `/token?grant_type=refresh_token`
  answer for a throwaway user.
- `gotrue_token_refresh_not_found_400.json`: refreshing with an
  already-rotated refresh token (`refresh_token_not_found`).
- `gotrue_token_refresh_invalid_400.json`: refreshing with a bogus token
  (`validation_failed`).
- `gotrue_signup_disabled_422.json`: `/signup` with sign-ups off
  (`signup_disabled`). The id-token grant answers a Google account with no
  Herbier user with the same code and envelope (GoTrue v2.197.0 source:
  `internal/api/external.go`, `NewUnprocessableEntityError(ErrorCodeSignupDisabled, …)`,
  returned unwrapped by `token_oidc.go`'s `case *HTTPError: return err`);
  not recorded, since it needs a real Google id token.
- `gotrue_token_id_token_invalid_request_400.json`: the id-token grant with
  a token that is not a Google one, the local Google provider on: GoTrue's
  OAuth-style `{"error":…,"error_description":…}` envelope.

No real access or refresh token outlives the script: the throwaway user and
its sessions are deleted at the end (also on error). The JWT in the 200 file
is a local-stack token (issuer `http://127.0.0.1:54321/auth/v1`), not a
secret.

`sync_<verb>_<table>[_<case>]_<status>.json`: PostgREST (Supabase, local
stack) answers for the sync requests of `app/sync_core/net/rest.ml`, read by
`test/sync/test_rest.ml`, recorded by `scripts/record-sync-fixtures.sh
[--force]` against the local stack (`npx supabase start`) with a throwaway
user `sync-fixtures@herbier.local`, deleted at the end with its rows (also on
error); no real account, no real token in any file. The script's requests
are written by hand to match those `Rest` renders (paths, `select=`,
`order=updated_at,id`, `Prefer`, `Range`, `Accept`), not checked against
them; it writes the answers byte for byte. It upserts one row
per table first, parents first (plants, tags, observations, photos,
plant_tags, plant_refs, reference; ids `01965d4e-0000-7000-8000-00000000000<1..7>`),
then the plant again with `notes` and its cover (the update path, answered
200). The row values are literal in the script and mirrored by the tests;
only `updated_at` is the server's. Then:

- `sync_select_<table>_200.json` ×7: each table, no filter.
- `sync_upsert_plants_bad_jwt_401.json`: `Authorization: Bearer
  not-a-jwt` (`PGRST301`).
- `sync_upsert_plants_anon_401.json`: no `Authorization` header (the
  `apikey` alone): `42501`, permission denied, answered 401 by this
  PostgREST version (the file is named after the status answered).
- `sync_upsert_observations_fk_409.json`: an observation whose
  `plant_id` points at no plant (`23503`).
- `sync_upsert_observations_check_400.json`: `lat` set without `lon`
  (`23514`, `observations_position_both_or_neither`).

Then the pull cases, read by `test/sync/test_cycle.ml`, recorded after the
files above (which they leave as they are). They share one run's rows and
server timestamps (pages 1 and 1_moved continue page 0's rows and ids, and
`Tag 001 bis` in page 1_moved is later than all of them), so the script
records all five again when one is missing:

- `sync_select_plants_empty_200.json`: the plants select filtered on
  `updated_at=gt.2100-01-01T00:00:00Z`: the real `[]` answer.
- `sync_select_tags_deleted_200.json`: the fixture tag soft-deleted by an
  upsert carrying `deleted_at`, then the tags select (one row, `deleted_at`
  set; its `updated_at` is the server's, later than the upsert's).
- `sync_select_tags_page0_200.json`, `sync_select_tags_page1_200.json`:
  500 more tags in one POST (`Tag 001` … `Tag 500`, ids
  `01965d4e-0000-7000-8000-000000001001` … `…1500`), then the tags select
  with `Range: 0-499` (500 rows: the deleted fixture tag and `Tag 001` …
  `Tag 499`) and `Range: 500-999` (`Tag 500`).
- `sync_select_tags_page1_moved_200.json`: `Tag 001` upserted again as
  `Tag 001 bis` (its `updated_at` moves last), then `Range: 500-999`: that
  tag a second time, the offset race of architecture §4.

The reference row's `payload` is sent with `vernacular` before `species` and
`rank` before `key` inside it; `sync_select_reference_200.json` shows
`jsonb`'s reorder (`species` first, `key` first inside it), which the
structural-equality tests of `test_rest.ml` and `test_merge.ml` rely on.

`drive_files_<verb>_<case>_<status>.json`: Google Drive v3 answers for
`Herbier_photos.Drive` (`error_of_answer`), read by `test/photos/test_drive.ml`
and, for the `files_get` ones, by `test/photos/test_health.ml` (the weekly
health check's program). The health tests also use
`drive_files_get_{present,trashed}_200.json` and
`drive_files_get_unknown_404.json` once the token run has recorded them, and
skip that case until then.
Two groups: the error answers below need no token and are recorded directly
with curl (no `Authorization` header, or `Bearer ya29.invalid`, which Google
always rejects); the 2xx success bodies need a real `drive.file` access token
and are recorded by `scripts/record-drive-fixtures.sh` with
`HERBIER_DRIVE_TOKEN`.

- `drive_files_get_no_token_403.json`: `GET
  https://www.googleapis.com/drive/v3/files/abc?fields=id,trashed`, no
  `Authorization` header: `403 PERMISSION_DENIED`, `errors[0].reason =
  "forbidden"`.
- `drive_files_get_invalid_token_401.json`: the same request with
  `Authorization: Bearer ya29.invalid`: `401 UNAUTHENTICATED`.
- `drive_files_create_invalid_token_401.json`: `POST
  …/upload/drive/v3/files?uploadType=multipart&fields=id,webViewLink` with
  `Bearer ya29.invalid` and a minimal multipart body: `401` (the same
  envelope; Drive rejects the token before reading the body).

No personal data in any of them: a throwaway `abc` file id and a token that
was never valid.

`capacitor_filesystem_readdir_{previews,refthumbs,missing}.json`: the
Capacitor Filesystem plugin's answers to `readdir` (« Libérer »), read
by `test/bindings/jsoo/cap_filesystem_smoke.ml` (and by its stub,
`filesystem_stub.js`, which resolves/rejects with them). Recorded on the
emulator (debug build, `@capacitor/filesystem` 8.1.5 over
`io.ionic.libs:ionfilesystem-android` 1.1.1) with `scripts/webview.mjs eval`
(not curl: no HTTP API is involved), then `python3 -m json.tool --indent 2`.
Every entry carries `name`, `type`, an integer `size` (a directory's too:
`File.length()`, 4096 on the emulator; the code ignores it), `mtime`, `ctime`
and `uri`. `readdir` and `rmdir` on a missing path both reject with code
`OS-PLUG-FILE-0008` (checked on the emulator for both calls) and a message of
the form `'readdir' failed because file at '<path>/' does not exist.` (the
code ignores the message). `refthumbs/` held two plant directories written
for the recording with `writeFile` (the plugin's answer is what is recorded,
not the files' origin), removed afterwards. Re-record (overwrite, same names)
with:

- `capacitor_filesystem_readdir_previews.json`:
  `Capacitor.Plugins.Filesystem.readdir({path:'previews',directory:'DATA'}).then(r => JSON.stringify(r))`.
- `capacitor_filesystem_readdir_refthumbs.json`:
  `Capacitor.Plugins.Filesystem.readdir({path:'refthumbs',directory:'DATA'}).then(r => JSON.stringify(r))` (one
  sub-directory per plant).
- `capacitor_filesystem_readdir_missing.json`:
  `Capacitor.Plugins.Filesystem.readdir({path:'nope',directory:'DATA'}).catch(e => JSON.stringify({code: e.code, message: e.message}))`.

`web/map/positron.json` (not in this directory: it is also the style the app
ships) is a recorded payload, read by `test/geo` as the fixture of its
`Style.with_overlays` tests; never hand-edited. It is re-recorded on demand
with `curl -sS https://tiles.openfreemap.org/styles/positron | python3 -m
json.tool > web/map/positron.json` (the server sends it minified; `json.tool`
only indents it, keeping key order).
