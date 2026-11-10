#!/usr/bin/env bash
# Regenerate web/fonts/material-symbols.woff2: Material Symbols Outlined
# reduced to the icons named in web/fonts/icons.txt, with the axes fixed at
# FILL 0, wght 400, GRAD 0, opsz 24 (the outlined look of the handoff).
#
#   scripts/subset-icons.sh
#
# Google Fonts does the subsetting (css2 `icon_names`), so no font tooling is
# needed locally; it wants the names sorted and comma-separated.
set -euo pipefail
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
fonts="$root/web/fonts"
names="$({ grep -v -e '^#' -e '^$' "$fonts/icons.txt" || true; } | tr -d '\r ' | LC_ALL=C sort -u | paste -sd, -)"
if [ -z "$names" ]; then
  echo "subset-icons: no icon names in $fonts/icons.txt" >&2
  exit 1
fi
# A woff2-capable user agent, or the css2 API answers with TrueType.
ua='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36'
css="$(curl -sSf -A "$ua" \
  "https://fonts.googleapis.com/css2?family=Material+Symbols+Outlined:opsz,wght,FILL,GRAD@24,400,0,0&icon_names=$names")"
url="$(printf '%s\n' "$css" | sed -n 's/.*src: url(\([^)]*\)) format(.woff2.).*/\1/p')"
if [ -z "$url" ] || [ "$(printf '%s\n' "$url" | wc -l)" -ne 1 ]; then
  echo "subset-icons: expected one woff2 URL in the css2 answer:" >&2
  printf '%s\n' "$css" >&2
  exit 1
fi
# Download beside the tracked font and replace it only once the file is
# complete and is a woff2, so a failure leaves the old font in place.
tmp="$(mktemp "$fonts/.material-symbols.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
curl -sSf --proto =https -o "$tmp" "$url"
if [ "$(head -c4 "$tmp")" != wOF2 ]; then
  echo "subset-icons: $url is not a woff2 file" >&2
  exit 1
fi
chmod 644 "$tmp"
mv "$tmp" "$fonts/material-symbols.woff2"
echo "subset-icons: $(wc -c <"$fonts/material-symbols.woff2") bytes, icons: $names"
