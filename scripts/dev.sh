#!/usr/bin/env bash
# Dev loop on a device or emulator: rebuild the web shell on every change,
# serve it from this machine, and point the app's web view at it.
#
#   scripts/dev.sh [host-ip] [port]
#
# The host IP must be reachable from the device (same Wi-Fi); defaults to
# the first non-loopback IPv4 address. Reload the page on the device to pick
# up a rebuild.
set -euo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
host="${1:-$(ipconfig getifaddr en0 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')}"
port="${2:-3000}"
dist=_build/default/web/dist
dune build @web
dune build @web --watch &
watch=$!
python3 -m http.server "$port" --bind 0.0.0.0 --directory "$dist" &
server=$!
trap 'kill $watch $server 2>/dev/null' EXIT
npx cap run android -l --host "$host" --port "$port"
