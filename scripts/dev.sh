#!/usr/bin/env bash
# Dev loop: rebuild the web shell on change and run the app on a device
# with live reload.
set -euo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
dune build @web --watch &
trap 'kill %1' EXIT
npx cap run android -l --external
