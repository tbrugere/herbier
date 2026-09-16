#!/usr/bin/env bash
# Release build: web shell, Capacitor sync, signed APK.
set -euo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
dune build --profile release @web
npx cap sync android
(cd android && ./gradlew assembleRelease)
