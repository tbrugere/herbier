Recorded payloads only: API responses (`gbif_<key>.json`,
`wikidata_<key>.json`, `wikipedia_<title>.json`, later `tela_<nn>.json`,
`inpn_<cd_nom>.json`) and exifr output (`exifr_<name>.json`, below). Never app
rows. Each API file is fetched once, committed, and never edited.

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
