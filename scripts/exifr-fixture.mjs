#!/usr/bin/env node
// Prints what Herbier_bindings.Exifr.parse returns for a photo, as the JSON
// text test/photos reads: node scripts/exifr-fixture.mjs photo.jpg >
// test/fixtures/exifr_<name>.json. `pick` is the list Herbier_photos.Exif.tags
// (app/photos/exif.ml), which test/photos checks; the other options must stay
// those of app/bindings/exifr.ml by hand.
import exifr from 'exifr';
import { readFileSync } from 'node:fs';

const [file] = process.argv.slice(2);
if (!file) {
  console.error('usage: node scripts/exifr-fixture.mjs <photo.jpg>');
  process.exit(2);
}
const tags = await exifr.parse(readFileSync(file), {
  pick: [
    'DateTimeOriginal',
    'OffsetTimeOriginal',
    'SubSecTimeOriginal',
    'GPSLatitude',
    'GPSLatitudeRef',
    'GPSLongitude',
    'GPSLongitudeRef',
    'GPSHPositioningError',
  ],
  reviveValues: false,
  translateValues: false,
});
console.log(JSON.stringify(tags ?? null, null, 2));
