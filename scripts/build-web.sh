#!/usr/bin/env bash
# Assemble the web shell into $2 from the sources next to this script's
# repo. Called by web/dune; $1 is the js_of_ocaml output for the app.
set -euo pipefail
app_js="$1"
out="$2"
# dune runs this inside _build (possibly in a sandbox copy); the repo root
# is everything before the first /_build/ segment of the working directory.
root="${PWD%%/_build/*}"
web="$root/web"
rm -rf "$out"
mkdir -p "$out"
out_abs="$(cd "$out" >/dev/null && pwd)"
cp "$web/index.html" "$out_abs/"
for d in fonts img map; do
  [ -d "$web/$d" ] && cp -R "$web/$d" "$out_abs/$d"
done
# Developer notes of web/fonts (the licences do ship with the fonts).
rm -f "$out_abs/fonts/README.md" "$out_abs/fonts/icons.txt"
(cd "$root" && npx --no-install sass --no-source-map "$web/sass/app.sass" "$out_abs/app.css")
(cd "$root" && npx --no-install esbuild "$web/js/vendor.js" --bundle --format=iife \
  --target=es2020 --minify --outfile="$out_abs/vendor.js")
# MapLibre 6's worker, set with setWorkerUrl in web/js/map.js. A .js name so
# the WebView's local server serves it as JavaScript (module workers need it).
worker="$root/node_modules/maplibre-gl/dist/maplibre-gl-worker.mjs"
cp "$worker" "$out_abs/maplibre-gl-worker.js"
test -s "$out_abs/maplibre-gl-worker.js"
test -f "$out_abs/vendor.css"
cp "$app_js" "$out_abs/app.js"
