#!/usr/bin/env bash
# Assemble the web shell into $2 from the sources next to this script's
# repo. Called by web/dune; $1 is the js_of_ocaml output for the app.
set -euo pipefail
app_js="$1"
out="$2"
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
web="$root/web"
rm -rf "$out"
mkdir -p "$out"
cp "$web/index.html" "$out/"
for d in fonts img map; do
  [ -d "$web/$d" ] && cp -R "$web/$d" "$out/$d"
done
(cd "$root" && npx --no-install sass --no-source-map "$web/sass/app.sass" "$PWD/$out/app.css")
(cd "$root" && npx --no-install esbuild "$web/js/vendor.js" --bundle --format=iife \
  --target=es2020 --minify --outfile="$PWD/$out/vendor.js")
cp "$app_js" "$out/app.js"
