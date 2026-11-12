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

`web/map/positron.json` (not in this directory: it is also the style the app
ships) is a recorded payload, read by `test/geo` as the fixture of its
`Style.with_overlays` tests; never hand-edited. It is re-recorded on demand
with `curl -sS https://tiles.openfreemap.org/styles/positron | python3 -m
json.tool > web/map/positron.json` (the server sends it minified; `json.tool`
only indents it, keeping key order).
