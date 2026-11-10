#!/usr/bin/env bash
# Release build: web shell, Capacitor sync, signed APK.
set -euo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
dune build --profile release @web
test -s _build/default/web/dist/app.js
if grep -q herbierDev _build/default/web/dist/app.js; then
  echo "release bundle contains dev pages (herbierDev)" >&2
  exit 1
fi
npx cap sync android
(cd android && ./gradlew assembleRelease)
