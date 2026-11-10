# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow"]
# ///
"""Writes the small JPEGs behind test/fixtures/exifr_pil_*.json, with the EXIF
tags their name says: uv run scripts/exif-fixture-jpegs.py <dir>, then
node scripts/exifr-fixture.mjs <dir>/<name>.jpg > test/fixtures/exifr_pil_<name>.json.
"""

import sys
from pathlib import Path

from PIL import Image
from PIL.ExifTags import GPS, IFD, Base

PHOTOS = {
    "offset_gps": {
        "exif": {
            Base.DateTimeOriginal: "2026:05:12 14:03:22",
            Base.OffsetTimeOriginal: "+02:00",
            Base.SubsecTimeOriginal: "417",
        },
        "gps": {
            GPS.GPSLatitudeRef: "N",
            GPS.GPSLatitude: (45.0, 10.0, 30.6),
            GPS.GPSLongitudeRef: "E",
            GPS.GPSLongitude: (5.0, 43.0, 12.0),
            GPS.GPSHPositioningError: 12.5,
        },
    },
    "no_offset_south_west": {
        "exif": {Base.DateTimeOriginal: "2025:11:30 08:15:00"},
        "gps": {
            GPS.GPSLatitudeRef: "S",
            GPS.GPSLatitude: (33.0, 51.0, 54.0),
            GPS.GPSLongitudeRef: "W",
            GPS.GPSLongitude: (70.0, 39.0, 0.0),
        },
    },
    "unset_clock_no_fix": {
        "exif": {Base.DateTimeOriginal: "0000:00:00 00:00:00"},
        "gps": {
            GPS.GPSLatitudeRef: "N",
            GPS.GPSLatitude: (0.0, 0.0, 0.0),
            GPS.GPSLongitudeRef: "E",
            GPS.GPSLongitude: (0.0, 0.0, 0.0),
        },
    },
}


def main(out: Path) -> None:
    out.mkdir(parents=True, exist_ok=True)
    for name, tags in PHOTOS.items():
        exif = Image.Exif()
        exif.get_ifd(IFD.Exif).update(tags["exif"])
        exif.get_ifd(IFD.GPSInfo).update(tags["gps"])
        Image.new("RGB", (8, 8), (90, 140, 60)).save(out / f"{name}.jpg", exif=exif)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: uv run scripts/exif-fixture-jpegs.py <dir>")
    main(Path(sys.argv[1]))
